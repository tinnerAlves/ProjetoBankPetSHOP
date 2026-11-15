-- =====================================================================
-- PETSHOP - Script do banco de dados (MySQL 8+)
-- Execute com um usuário administrador (NÃO use root na aplicação).
-- O script recria o banco e os usuários, então pode ser executado de novo.
-- =====================================================================
-- Necessário para criar funções com o binlog ativo (exige privilégio de administrador).
SET NAMES utf8mb4;
SET GLOBAL log_bin_trust_function_creators = 1;

DROP DATABASE IF EXISTS petshop;
CREATE DATABASE petshop CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE petshop;
DROP USER IF EXISTS 'petshop_admin'@'localhost';
CREATE USER 'petshop_admin'@'localhost' IDENTIFIED BY 'Troque#Admin2026';
GRANT ALL PRIVILEGES ON petshop.* TO 'petshop_admin'@'localhost';

-- ---------------------------------------------------------------------
-- 1. GERAÇÃO DE IDs (regra própria: PREFIXO-000001)
-- Justificativa: IDs legíveis, independentes do banco, sem lacunas
-- (o rollback desfaz o incremento) e atômicos (lock de linha).
-- ---------------------------------------------------------------------
CREATE TABLE sequencias (
  nome         VARCHAR(30) PRIMARY KEY,
  prefixo      VARCHAR(5)  NOT NULL,
  ultimo_valor INT UNSIGNED NOT NULL DEFAULT 0
) ENGINE=InnoDB;

INSERT INTO sequencias (nome, prefixo) VALUES
 ('grupo','GRP'),('usuario','USR'),('cliente','CLI'),('pet','PET'),
 ('produto','PRD'),('servico','SRV'),('agendamento','AGD'),('venda','VND');

DELIMITER $$
CREATE FUNCTION fn_gerar_id(p_nome VARCHAR(30)) RETURNS VARCHAR(20)
  NOT DETERMINISTIC MODIFIES SQL DATA
BEGIN
  DECLARE v_prefixo VARCHAR(5);
  DECLARE v_num INT UNSIGNED;
  UPDATE sequencias SET ultimo_valor = LAST_INSERT_ID(ultimo_valor + 1)
   WHERE nome = p_nome;
  IF ROW_COUNT() = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Sequência inexistente';
  END IF;
  SET v_num = LAST_INSERT_ID();
  SELECT prefixo INTO v_prefixo FROM sequencias WHERE nome = p_nome;
  RETURN CONCAT(v_prefixo, '-', LPAD(v_num, 6, '0'));
END$$
DELIMITER ;

-- ---------------------------------------------------------------------
-- 2. TABELAS
-- AUTO_INCREMENT usado apenas em itens_venda e log_precos (dados de
-- apoio, não críticos, sem identificação externa).
-- ---------------------------------------------------------------------
CREATE TABLE grupos_usuarios (
  id_grupo     VARCHAR(20) PRIMARY KEY,
  nome         VARCHAR(50) NOT NULL UNIQUE,
  descricao    VARCHAR(200),
  nivel_acesso ENUM('ADMIN','GERENTE','ATENDENTE') NOT NULL
) ENGINE=InnoDB;

CREATE TABLE usuarios (
  id_usuario  VARCHAR(20) PRIMARY KEY,
  id_grupo    VARCHAR(20) NOT NULL,
  nome        VARCHAR(100) NOT NULL,
  email       VARCHAR(120) NOT NULL UNIQUE,
  senha_hash  CHAR(60) NOT NULL,            -- bcrypt
  ativo       TINYINT(1) NOT NULL DEFAULT 1,
  criado_em   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_usuarios_grupo FOREIGN KEY (id_grupo) REFERENCES grupos_usuarios(id_grupo)
) ENGINE=InnoDB;

CREATE TABLE clientes (
  id_cliente VARCHAR(20) PRIMARY KEY,
  nome       VARCHAR(100) NOT NULL,
  cpf        CHAR(11) NOT NULL UNIQUE,
  telefone   VARCHAR(20),
  email      VARCHAR(120),
  criado_em  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE pets (
  id_pet          VARCHAR(20) PRIMARY KEY,
  id_cliente      VARCHAR(20) NOT NULL,
  nome            VARCHAR(60) NOT NULL,
  especie         ENUM('CAO','GATO','AVE','ROEDOR','OUTRO') NOT NULL,
  raca            VARCHAR(60),
  data_nascimento DATE,
  peso_kg         DECIMAL(5,2),
  CONSTRAINT fk_pets_cliente FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente)
) ENGINE=InnoDB;

CREATE TABLE servicos (
  id_servico  VARCHAR(20) PRIMARY KEY,
  nome        VARCHAR(80) NOT NULL UNIQUE,
  preco       DECIMAL(10,2) NOT NULL CHECK (preco >= 0),
  duracao_min INT NOT NULL CHECK (duracao_min > 0)
) ENGINE=InnoDB;

CREATE TABLE produtos (
  id_produto     VARCHAR(20) PRIMARY KEY,
  nome           VARCHAR(100) NOT NULL,
  categoria      VARCHAR(50) NOT NULL,
  preco          DECIMAL(10,2) NOT NULL CHECK (preco >= 0),
  estoque        INT NOT NULL DEFAULT 0 CHECK (estoque >= 0),
  estoque_minimo INT NOT NULL DEFAULT 5
) ENGINE=InnoDB;

CREATE TABLE agendamentos (
  id_agendamento VARCHAR(20) PRIMARY KEY,
  id_pet         VARCHAR(20) NOT NULL,
  id_servico     VARCHAR(20) NOT NULL,
  id_usuario     VARCHAR(20) NOT NULL,       -- profissional responsável
  data_hora      DATETIME NOT NULL,
  status         ENUM('AGENDADO','CONCLUIDO','CANCELADO') NOT NULL DEFAULT 'AGENDADO',
  observacoes    VARCHAR(255),
  CONSTRAINT fk_agd_pet     FOREIGN KEY (id_pet)     REFERENCES pets(id_pet),
  CONSTRAINT fk_agd_servico FOREIGN KEY (id_servico) REFERENCES servicos(id_servico),
  CONSTRAINT fk_agd_usuario FOREIGN KEY (id_usuario) REFERENCES usuarios(id_usuario)
) ENGINE=InnoDB;

CREATE TABLE vendas (
  id_venda   VARCHAR(20) PRIMARY KEY,
  id_cliente VARCHAR(20) NOT NULL,
  id_usuario VARCHAR(20) NOT NULL,
  data_venda DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  total      DECIMAL(12,2) NOT NULL DEFAULT 0,
  status     ENUM('ABERTA','FINALIZADA','CANCELADA') NOT NULL DEFAULT 'ABERTA',
  CONSTRAINT fk_vendas_cliente FOREIGN KEY (id_cliente) REFERENCES clientes(id_cliente),
  CONSTRAINT fk_vendas_usuario FOREIGN KEY (id_usuario) REFERENCES usuarios(id_usuario)
) ENGINE=InnoDB;

CREATE TABLE itens_venda (
  id_item    BIGINT AUTO_INCREMENT PRIMARY KEY,
  id_venda   VARCHAR(20) NOT NULL,
  id_produto VARCHAR(20) NOT NULL,
  quantidade INT NOT NULL CHECK (quantidade > 0),
  preco_unit DECIMAL(10,2) NOT NULL,
  CONSTRAINT fk_item_venda   FOREIGN KEY (id_venda)   REFERENCES vendas(id_venda),
  CONSTRAINT fk_item_produto FOREIGN KEY (id_produto) REFERENCES produtos(id_produto)
) ENGINE=InnoDB;

CREATE TABLE log_precos (
  id_log       BIGINT AUTO_INCREMENT PRIMARY KEY,
  id_produto   VARCHAR(20) NOT NULL,
  preco_antigo DECIMAL(10,2) NOT NULL,
  preco_novo   DECIMAL(10,2) NOT NULL,
  alterado_em  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  alterado_por VARCHAR(100) NOT NULL
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 3. ÍNDICES (além de PK/UNIQUE/FK já indexados automaticamente)
-- ---------------------------------------------------------------------
-- Agenda do dia/semana e verificação de conflito de horário por profissional
CREATE INDEX idx_agd_prof_data   ON agendamentos (id_usuario, data_hora);
-- Listagem da agenda filtrando por status e data
CREATE INDEX idx_agd_status_data ON agendamentos (status, data_hora);
-- Busca de produtos por nome na tela de vendas
CREATE INDEX idx_produtos_nome   ON produtos (nome);
-- Relatórios de vendas por período
CREATE INDEX idx_vendas_data     ON vendas (data_venda);
-- Busca de clientes por nome
CREATE INDEX idx_clientes_nome   ON clientes (nome);

-- ---------------------------------------------------------------------
-- 4. FUNCTION auxiliar
-- ---------------------------------------------------------------------
DELIMITER $$
CREATE FUNCTION fn_total_venda(p_id_venda VARCHAR(20)) RETURNS DECIMAL(12,2)
  READS SQL DATA
BEGIN
  DECLARE v_total DECIMAL(12,2);
  SELECT COALESCE(SUM(quantidade * preco_unit), 0) INTO v_total
    FROM itens_venda WHERE id_venda = p_id_venda;
  RETURN v_total;
END$$
DELIMITER ;

-- ---------------------------------------------------------------------
-- 5. TRIGGERS
-- ---------------------------------------------------------------------
DELIMITER $$
-- Impede vender mais do que o estoque disponível (regra de integridade)
CREATE TRIGGER trg_itens_venda_bi BEFORE INSERT ON itens_venda
FOR EACH ROW
BEGIN
  DECLARE v_estoque INT;
  SELECT estoque INTO v_estoque FROM produtos WHERE id_produto = NEW.id_produto FOR UPDATE;
  IF v_estoque IS NULL OR v_estoque < NEW.quantidade THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Estoque insuficiente';
  END IF;
END$$

-- Baixa automática de estoque após inserir item
CREATE TRIGGER trg_itens_venda_ai AFTER INSERT ON itens_venda
FOR EACH ROW
BEGIN
  UPDATE produtos SET estoque = estoque - NEW.quantidade
   WHERE id_produto = NEW.id_produto;
END$$

-- Auditoria de alteração de preço
CREATE TRIGGER trg_produtos_bu BEFORE UPDATE ON produtos
FOR EACH ROW
BEGIN
  IF OLD.preco <> NEW.preco THEN
    INSERT INTO log_precos (id_produto, preco_antigo, preco_novo, alterado_por)
    VALUES (OLD.id_produto, OLD.preco, NEW.preco, USER());
  END IF;
END$$
DELIMITER ;

-- ---------------------------------------------------------------------
-- 6. VIEWS
-- ---------------------------------------------------------------------
-- Agenda completa (junta 5 tabelas: evita JOINs repetidos na aplicação)
CREATE VIEW vw_agenda AS
SELECT a.id_agendamento, a.data_hora, a.status,
       p.nome AS pet, p.especie, c.nome AS cliente, c.telefone,
       s.nome AS servico, s.preco, u.nome AS profissional
  FROM agendamentos a
  JOIN pets p     ON p.id_pet = a.id_pet
  JOIN clientes c ON c.id_cliente = p.id_cliente
  JOIN servicos s ON s.id_servico = a.id_servico
  JOIN usuarios u ON u.id_usuario = a.id_usuario;

-- Produtos que precisam de reposição (apoio à gestão)
CREATE VIEW vw_estoque_baixo AS
SELECT id_produto, nome, categoria, estoque, estoque_minimo
  FROM produtos
 WHERE estoque <= estoque_minimo;

-- Resumo de vendas sem expor dados sensíveis (perfil de relatórios)
CREATE VIEW vw_vendas_resumo AS
SELECT v.id_venda, v.data_venda, v.status, c.nome AS cliente,
       COALESCE(SUM(i.quantidade), 0) AS qtd_itens, v.total
  FROM vendas v
  JOIN clientes c ON c.id_cliente = v.id_cliente
  LEFT JOIN itens_venda i ON i.id_venda = v.id_venda
 GROUP BY v.id_venda, v.data_venda, v.status, c.nome, v.total;

-- ---------------------------------------------------------------------
-- 7. PROCEDURES (com controle transacional - TCL)
-- ---------------------------------------------------------------------
DELIMITER $$

-- Cadastra cliente + primeiro pet de forma atômica
CREATE PROCEDURE sp_cadastrar_cliente_com_pet(
  IN p_nome VARCHAR(100), IN p_cpf CHAR(11), IN p_telefone VARCHAR(20),
  IN p_email VARCHAR(120), IN p_pet_nome VARCHAR(60),
  IN p_especie VARCHAR(10), IN p_raca VARCHAR(60),
  OUT p_id_cliente VARCHAR(20))
BEGIN
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN ROLLBACK; RESIGNAL; END;

  START TRANSACTION;
    SET p_id_cliente = fn_gerar_id('cliente');
    INSERT INTO clientes (id_cliente, nome, cpf, telefone, email)
    VALUES (p_id_cliente, p_nome, p_cpf, p_telefone, p_email);
    INSERT INTO pets (id_pet, id_cliente, nome, especie, raca)
    VALUES (fn_gerar_id('pet'), p_id_cliente, p_pet_nome, p_especie, p_raca);
  COMMIT;
END$$

CREATE PROCEDURE sp_abrir_venda(
  IN p_id_cliente VARCHAR(20), IN p_id_usuario VARCHAR(20),
  OUT p_id_venda VARCHAR(20))
BEGIN
  SET p_id_venda = fn_gerar_id('venda');
  INSERT INTO vendas (id_venda, id_cliente, id_usuario)
  VALUES (p_id_venda, p_id_cliente, p_id_usuario);
END$$

-- Adiciona item: trigger valida/baixa estoque; qualquer erro => ROLLBACK
CREATE PROCEDURE sp_adicionar_item(
  IN p_id_venda VARCHAR(20), IN p_id_produto VARCHAR(20), IN p_qtd INT)
BEGIN
  DECLARE v_preco DECIMAL(10,2);
  DECLARE v_status VARCHAR(20);
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN ROLLBACK; RESIGNAL; END;

  START TRANSACTION;
    SELECT status INTO v_status FROM vendas WHERE id_venda = p_id_venda FOR UPDATE;
    IF v_status IS NULL OR v_status <> 'ABERTA' THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Venda inexistente ou não está aberta';
    END IF;
    SELECT preco INTO v_preco FROM produtos WHERE id_produto = p_id_produto;
    INSERT INTO itens_venda (id_venda, id_produto, quantidade, preco_unit)
    VALUES (p_id_venda, p_id_produto, p_qtd, v_preco);
    UPDATE vendas SET total = fn_total_venda(p_id_venda) WHERE id_venda = p_id_venda;
  COMMIT;
END$$

-- Agenda serviço verificando conflito de horário do profissional
CREATE PROCEDURE sp_agendar_servico(
  IN p_id_pet VARCHAR(20), IN p_id_servico VARCHAR(20),
  IN p_id_usuario VARCHAR(20), IN p_data_hora DATETIME,
  OUT p_id_agendamento VARCHAR(20))
BEGIN
  DECLARE v_dur INT;
  DECLARE v_conflitos INT;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN ROLLBACK; RESIGNAL; END;

  START TRANSACTION;
    SELECT duracao_min INTO v_dur FROM servicos WHERE id_servico = p_id_servico;
    SELECT COUNT(*) INTO v_conflitos
      FROM agendamentos a JOIN servicos s ON s.id_servico = a.id_servico
     WHERE a.id_usuario = p_id_usuario AND a.status = 'AGENDADO'
       AND p_data_hora < DATE_ADD(a.data_hora, INTERVAL s.duracao_min MINUTE)
       AND DATE_ADD(p_data_hora, INTERVAL v_dur MINUTE) > a.data_hora
     FOR UPDATE;
    IF v_conflitos > 0 THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Profissional já possui agendamento neste horário';
    END IF;
    SET p_id_agendamento = fn_gerar_id('agendamento');
    INSERT INTO agendamentos (id_agendamento, id_pet, id_servico, id_usuario, data_hora)
    VALUES (p_id_agendamento, p_id_pet, p_id_servico, p_id_usuario, p_data_hora);
  COMMIT;
END$$

CREATE PROCEDURE sp_finalizar_venda(IN p_id_venda VARCHAR(20))
BEGIN
  UPDATE vendas SET status = 'FINALIZADA' WHERE id_venda = p_id_venda AND status = 'ABERTA';
END$$
DELIMITER ;

-- ---------------------------------------------------------------------
-- 8. USUÁRIOS E CONTROLE DE ACESSO (princípio do menor privilégio)
-- Troque as senhas antes de usar!
-- ---------------------------------------------------------------------
-- Administrador do banco (migrações/manutenção) - restrito ao schema


-- Usuário da APLICAÇÃO: lê tudo, escreve só em cadastros; vendas e
-- agendamentos SOMENTE via procedures. Sem DELETE, sem DDL.
DROP USER IF EXISTS 'petshop_app'@'localhost';
CREATE USER 'petshop_app'@'localhost'       IDENTIFIED BY 'Troque#App2026';
GRANT SELECT ON petshop.* TO 'petshop_app'@'localhost';
GRANT INSERT, UPDATE ON petshop.clientes TO 'petshop_app'@'localhost';
GRANT INSERT, UPDATE ON petshop.pets     TO 'petshop_app'@'localhost';
GRANT INSERT, UPDATE ON petshop.produtos TO 'petshop_app'@'localhost';
GRANT EXECUTE ON petshop.* TO 'petshop_app'@'localhost';

-- Usuário de relatórios: apenas VIEWS (somente leitura)
DROP USER IF EXISTS 'petshop_relatorio'@'localhost';
CREATE USER 'petshop_relatorio'@'localhost' IDENTIFIED BY 'Troque#Rel2026';
GRANT SELECT ON petshop.vw_agenda         TO 'petshop_relatorio'@'localhost';
GRANT SELECT ON petshop.vw_estoque_baixo  TO 'petshop_relatorio'@'localhost';
GRANT SELECT ON petshop.vw_vendas_resumo  TO 'petshop_relatorio'@'localhost';

FLUSH PRIVILEGES;

-- ---------------------------------------------------------------------
-- 9. DADOS DE EXEMPLO
-- ---------------------------------------------------------------------
INSERT INTO grupos_usuarios VALUES
 (fn_gerar_id('grupo'),'Administradores','Acesso total ao sistema','ADMIN'),
 (fn_gerar_id('grupo'),'Gerentes','Gestão de estoque e relatórios','GERENTE'),
 (fn_gerar_id('grupo'),'Atendentes','Vendas e agendamentos','ATENDENTE');

INSERT INTO usuarios (id_usuario,id_grupo,nome,email,senha_hash) VALUES
 (fn_gerar_id('usuario'),'GRP-000001','Ana Admin','ana@petshop.com',  REPEAT('x',60)),
 (fn_gerar_id('usuario'),'GRP-000003','Bruno Tosador','bruno@petshop.com', REPEAT('x',60));

INSERT INTO servicos VALUES
 (fn_gerar_id('servico'),'Banho',50.00,40),
 (fn_gerar_id('servico'),'Tosa',70.00,60),
 (fn_gerar_id('servico'),'Consulta veterinária',120.00,30);

INSERT INTO produtos (id_produto,nome,categoria,preco,estoque,estoque_minimo) VALUES
 (fn_gerar_id('produto'),'Ração Premium 10kg','Ração',189.90,20,5),
 (fn_gerar_id('produto'),'Coleira Média','Acessórios',35.00,3,5),
 (fn_gerar_id('produto'),'Shampoo Neutro','Higiene',22.50,15,5);

CALL sp_cadastrar_cliente_com_pet('Maria Silva','12345678901','61999990000','maria@email.com','Thor','CAO','Golden Retriever',@cli);
CALL sp_agendar_servico('PET-000001','SRV-000001','USR-000002','2026-11-20 10:00:00',@agd);
CALL sp_abrir_venda(@cli,'USR-000002',@vnd);
CALL sp_adicionar_item(@vnd,'PRD-000001',2);
CALL sp_finalizar_venda(@vnd);

-- ---------------------------------------------------------------------
-- 10. DEMONSTRAÇÃO DE TCL PARA A APRESENTAÇÃO
-- ---------------------------------------------------------------------
-- START TRANSACTION;
--   UPDATE produtos SET estoque = estoque - 1 WHERE id_produto='PRD-000003';
--   SELECT estoque FROM produtos WHERE id_produto='PRD-000003';
-- ROLLBACK;   -- desfaz; repita com COMMIT para efetivar
-- CALL sp_adicionar_item(@vnd,'PRD-000002',99);  -- falha: estoque insuficiente (ROLLBACK automático)
