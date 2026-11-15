# PetShop – aplicação (Node.js + Express + MySQL)

## Como rodar
1. Execute `petshop.sql` no MySQL (cria banco, objetos e usuários).
2. `cp .env.example .env` e ajuste a senha do `petshop_app`.
3. `npm install`
4. `npm start` e abra http://localhost:3000

A API recusa iniciar se `DB_USER=root`. O cabeçalho da tela mostra o usuário
real da conexão (`CURRENT_USER()`), como evidência para a apresentação.

## Onde cada requisito aparece
- View: aba Agenda (`vw_agenda`) e aba Estoque baixo (`vw_estoque_baixo`)
- Entidade: aba Clientes (`clientes`)
- Procedure + TCL: cadastro de cliente+pet e agendamento (erro de conflito exibido na tela)
# ProjetoBankPetSHOP
