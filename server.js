require('dotenv').config();
const express = require('express');
const mysql = require('mysql2/promise');

if (process.env.DB_USER === 'root') {
  console.error('Uso do usuário root é proibido. Configure DB_USER=petshop_app.');
  process.exit(1);
}

const pool = mysql.createPool({
  host: process.env.DB_HOST, port: process.env.DB_PORT,
  database: process.env.DB_NAME, user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  dateStrings: true, connectionLimit: 10
});

const app = express();
app.use(express.json());
app.use(express.static('public'));

// Converte erros do MySQL em respostas HTTP claras
const wrap = fn => async (req, res) => {
  try { await fn(req, res); }
  catch (e) {
    if (e.sqlState === '45000') return res.status(400).json({ erro: e.sqlMessage });
    if (e.errno === 1062) return res.status(409).json({ erro: 'Registro duplicado (CPF ou e-mail já cadastrado).' });
    if (e.errno === 1452) return res.status(400).json({ erro: 'Referência inválida (pet, serviço ou profissional).' });
    console.error(e);
    res.status(500).json({ erro: 'Erro interno ao acessar o banco de dados.' });
  }
};

// Evidência de que a conexão NÃO é root (usada no cabeçalho da tela)
app.get('/api/whoami', wrap(async (_req, res) => {
  const [[r]] = await pool.query('SELECT CURRENT_USER() AS usuario, DATABASE() AS banco');
  res.json(r);
}));

// VIEW: agenda completa
app.get('/api/agenda', wrap(async (_req, res) => {
  const [rows] = await pool.query('SELECT * FROM vw_agenda ORDER BY data_hora');
  res.json(rows);
}));

// VIEW: estoque baixo
app.get('/api/estoque-baixo', wrap(async (_req, res) => {
  const [rows] = await pool.query('SELECT * FROM vw_estoque_baixo ORDER BY estoque');
  res.json(rows);
}));

// ENTIDADE: clientes (com contagem de pets)
app.get('/api/clientes', wrap(async (req, res) => {
  const busca = `%${req.query.busca || ''}%`;
  const [rows] = await pool.query(
    `SELECT c.id_cliente, c.nome, c.cpf, c.telefone, c.email, COUNT(p.id_pet) AS pets
       FROM clientes c LEFT JOIN pets p ON p.id_cliente = c.id_cliente
      WHERE c.nome LIKE ? GROUP BY c.id_cliente ORDER BY c.nome`, [busca]);
  res.json(rows);
}));

// PROCEDURE + TCL: cliente e primeiro pet na mesma transação
app.post('/api/clientes', wrap(async (req, res) => {
  const { nome, cpf, telefone, email, petNome, especie, raca } = req.body;
  if (!nome || !/^\d{11}$/.test(cpf || '') || !petNome || !especie)
    return res.status(400).json({ erro: 'Informe nome, CPF (11 dígitos), nome e espécie do pet.' });
  const conn = await pool.getConnection(); // OUT param exige a mesma conexão
  try {
    await conn.query('CALL sp_cadastrar_cliente_com_pet(?,?,?,?,?,?,?,@id)',
      [nome, cpf, telefone || null, email || null, petNome, especie, raca || null]);
    const [[r]] = await conn.query('SELECT @id AS id');
    res.status(201).json({ id_cliente: r.id });
  } finally { conn.release(); }
}));

// Listas de apoio ao formulário de agendamento
app.get('/api/pets', wrap(async (_req, res) => {
  const [rows] = await pool.query(
    `SELECT p.id_pet, CONCAT(p.nome, ' (', c.nome, ')') AS rotulo
       FROM pets p JOIN clientes c ON c.id_cliente = p.id_cliente ORDER BY p.nome`);
  res.json(rows);
}));
app.get('/api/servicos', wrap(async (_req, res) => {
  const [rows] = await pool.query('SELECT id_servico, nome, preco, duracao_min FROM servicos ORDER BY nome');
  res.json(rows);
}));
app.get('/api/profissionais', wrap(async (_req, res) => {
  // nunca expõe senha_hash
  const [rows] = await pool.query('SELECT id_usuario, nome FROM usuarios WHERE ativo = 1 ORDER BY nome');
  res.json(rows);
}));

// PROCEDURE + TCL: agenda com verificação de conflito
app.post('/api/agendamentos', wrap(async (req, res) => {
  const { idPet, idServico, idUsuario, dataHora } = req.body;
  if (!idPet || !idServico || !idUsuario || !dataHora)
    return res.status(400).json({ erro: 'Preencha todos os campos do agendamento.' });
  const conn = await pool.getConnection();
  try {
    await conn.query('CALL sp_agendar_servico(?,?,?,?,@id)', [idPet, idServico, idUsuario, dataHora]);
    const [[r]] = await conn.query('SELECT @id AS id');
    res.status(201).json({ id_agendamento: r.id });
  } finally { conn.release(); }
}));

app.listen(process.env.PORT || 3000, () =>
  console.log(`PetShop em http://localhost:${process.env.PORT || 3000} (usuário do banco: ${process.env.DB_USER})`));
