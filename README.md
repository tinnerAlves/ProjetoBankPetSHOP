# PetShop – aplicação (Node.js + Express + MySQL)

Projeto da disciplina Laboratório de Banco de Dados.

## Como rodar
1. Com um usuário administrador do MySQL, execute `petshop.sql`. Ele recria o banco `petshop`, os objetos e os usuários, e pode ser executado de novo.
2. `cp .env.example .env` e informe a senha do `petshop_app` (a mesma definida no script).
3. `npm install`
4. `npm start` e abra http://localhost:3000

A API recusa iniciar se `DB_USER=root`. O cabeçalho da tela mostra o usuário
real da conexão (`CURRENT_USER()`), como evidência para a apresentação.

## Usuários do banco
- `petshop_admin`: todos os privilégios, só no esquema `petshop`.
- `petshop_app`: usado pela aplicação; lê as tabelas, grava em clientes, pets e produtos, executa as procedures; sem DELETE e sem DDL.
- `petshop_relatorio`: somente leitura nas views.

## Onde cada requisito aparece
- View: aba Agenda (`vw_agenda`) e aba Estoque baixo (`vw_estoque_baixo`)
- Entidade: aba Clientes (`clientes`)
- Procedure + TCL: cadastro de cliente+pet e agendamento (erro de conflito exibido na tela)
- Vendas, triggers de estoque e log de preços: no banco, demonstrados por SQL (a interface não tem tela de vendas)
