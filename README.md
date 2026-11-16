# PetShop – aplicação (Node.js + Express + MySQL)

Projeto da disciplina Laboratório de Banco de Dados.

## Como rodar
1. Com um usuário administrador do MySQL, execute `petshop.sql`. Ele recria o banco `petshop`, os objetos e os usuários, e pode ser executado de novo.
2.  `cp .env.example .env` e informe a senha do `petshop_app` (a mesma definida no script).

3. O arquivo `.env.example` serve apenas como um modelo de configuração. Para que o projeto funcione, você precisa criar um arquivo `.env` real na **pasta raiz do projeto** (mesmo local onde está o `.env.example`).
-------------
#### Como criar o arquivo `.env` no Windows:
  Abra a **pasta raiz do projeto** no Explorador de Arquivos.
   Clique com o **botão direito** em um espaço vazio > **Novo** > **Documento de Texto**.
   Pressione `Ctrl + A` para selecionar todo o nome do arquivo (incluindo e esse cara que a gente quer mudar `.txt`), digite exatamente `.env` e pressione **Enter** *(confirme caso o Windows pergunte se deseja alterar a extensão)*.
   Abra o arquivo `.env.example` no bloco de nota, copie todo o seu conteúdo e cole dentro do novo arquivo `.env` no bloco de nota.
   No arquivo `.env`, substitua o valor da senha pela senha configurada no seu banco de dados:
   ```env
   DB_PASSWORD="defina_a_senha_do_petshop_app"
-------------
4. `npm install`
5. `npm start` e abra http://localhost:3000

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
