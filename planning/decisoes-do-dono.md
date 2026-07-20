# Decisões que esperam pelo dono

**Para quem é este documento:** para o dono do projeto, que não precisa ser
técnico para decidir bem. A regra número 6 do roadmap diz que **nenhuma decisão
é aceita sem o dono** — este arquivo é a fila dessas decisões, em linguagem
simples, com a recomendação de quem estudou o problema e o que acontece se você
não decidir nada.

Atualizado em **2026-07-20**. Quando uma decisão for tomada, ela sai daqui e
vira um ADR ACEITO em `adrs.md` (o registro técnico permanente).

---

## Como decidir sem ser técnico

Três perguntas que você pode fazer sobre **qualquer** proposta, e que o projeto
se obriga a responder:

1. **"Qual medição sustenta isso?"** — neste projeto, performance se decide com
   números medidos aqui dentro, nunca com "o framework X faz assim".
2. **"O que acontece se a gente se arrepender?"** — toda proposta deve dizer o
   custo de reverter. Desconfie de tudo que é "difícil de desfazer".
3. **"Qual teste falharia sem essa mudança?"** — se ninguém sabe responder, a
   mudança provavelmente não é necessária ainda.

---

## Decisões abertas AGORA

### 1. ADR-028 — guardar ou não um valor por requisição (a mais importante)

**O problema em linguagem simples.** Quando alguém faz login, um "porteiro"
(middleware de autenticação) confere o crachá (o token). Hoje, o porteiro
confere o crachá e **joga fora o resultado** — cada sala seguinte (cada função
que precisa saber quem é o usuário) confere o crachá de novo. Com crachás
simples isso custa quase nada; se um dia a conferência consultar o banco de
dados, seriam várias consultas repetidas por requisição.

**As opções.**
- **A — deixar como está, para sempre.** O custo da reconferência é aceito e
  documentado. Não muda nada no código. É a única opção 100% reversível:
  adicionar um mecanismo depois é fácil; retirar um mecanismo que as aplicações
  já usam quebra todas elas.
- **B — um pequeno "bolso" fixo por requisição** para guardar valores tipados.
- **C — um único "escaninho" tipado** para exatamente um valor.

**Recomendação registrada no ADR: opção A**, até que exista um programa real
(não hipotético) que não consiga ser escrito de forma limpa hoje. Um dado do
mundo real que apoia a calma: o único aplicativo Odin de terceiros que
encontramos usando o mesmo backend (`coffees_odin`) paga esse mesmo custo de
reconferência e funciona normalmente.

**Se você não decidir nada:** vale a opção A na prática, e a Fase 3 (WP37)
implementa só o que o ADR-004 já aprovou (estado da aplicação, não da
requisição). Sem pressa real aqui.

### 2. CI no GitHub — rodar o gate automaticamente a cada mudança?

**O problema em linguagem simples.** O projeto tem um "detector de mentiras"
excelente (`build/check.sh`) que verifica tudo — mas ele só roda quando alguém
lembra de rodar, na máquina local ou no seu VPS. Existe inclusive uma decisão
sua registrada no gate: *"GitHub Actions não é gate obrigatório deste projeto"*
— o arquivo `.github/workflows` é proibido hoje.

**A favor de ligar o CI:** toda mudança enviada ao GitHub seria verificada
sozinha, com o compilador exato pinado em `odin-version.txt`; um PR com defeito
apareceria vermelho sem depender de ninguém lembrar de nada.

**Contra:** é um serviço externo (minutos do GitHub Actions; gratuito para
repositório público), e o gate local/VPS continua sendo a fonte da verdade —
o CI seria uma cópia de conveniência, nunca o juiz.

**Se você não decidir nada:** continua tudo como está (sem CI). Um workflow
pronto ficou preparado fora do repositório, para o caso de você dizer sim.

### 3. ADR-010 — a "API avançada" (adiada, sem pressa)

Existe uma proposta antiga de oferecer uma porta de entrada avançada
(`app_init`, configuração avançada) separada da API comum. Está **adiada de
propósito** e só precisa de decisão se/quando um usuário real pedir. Nenhuma
ação necessária agora.

### 4. ADR-013 — proxies confiáveis (só na Fase 4)

Quando o servidor roda atrás de um proxy (nginx, Cloudflare…), descobrir o IP
real do cliente é uma decisão de **segurança** — cabeçalhos podem ser
falsificados. A regra já pesquisada: por padrão, confiar só no endereço da
conexão; qualquer proxy confiável é configuração explícita do operador. Decida
quando a Fase 4 começar, não antes.

---

## O que a Fase 3 vai te pedir (prepare-se, sem decidir agora)

O plano da Fase 3 (`phase-3-plan.md`) marca estes pontos como "aprovação do
dono". Em ordem provável de chegada:

| Pedido | Em linguagem simples | O que exigir antes de aprovar |
|---|---|---|
| **WP31a — normalização de caminhos** | `/users` e `/users/` são a mesma coisa? E `%2F`? Hoje, nada é normalizado, de propósito. É decisão de **segurança** (é onde vivem bugs de path traversal). | Os testes de controle negativo já nomeados no plano (o "corpus"), passando. |
| **WP32a — HEAD, OPTIONS e 501** | Responder automaticamente a dois tipos de requisição que todo servidor HTTP "de verdade" deveria responder. | Que o OPTIONS reutilize a máquina do `Allow` que já existe, sem criar uma segunda. |
| **WP34 — nome da rota para métricas** | Um acessor público (+1 símbolo) para a aplicação saber "qual rota atendeu" — destrava observabilidade (OpenTelemetry exige). | A regra de redação: expor o **padrão** (`/users/:id`), nunca o caminho real (`/users/123`). |
| **WP36 — limites configuráveis** | Hoje o limite de corpo é fixo em 4 MiB. Passa a ser configurável via struct de opções com padrão sensato. | A menor struct possível (cada campo é uma promessa eterna) e o ledger de capacidade atualizado **no mesmo commit**. |
| **WP37 — estado tipado** | Implementa o que o ADR-004 já aprovou; a parte nova depende do ADR-028 acima. | Que nada assuma o ADR-028 antes de você decidi-lo. |
| **WP38 — congelamento da Fase 3** | O fecho da fase: ledgers, benchmark de regressão no gate, laboratório de uso re-medido. | Se o programa-guia passar de 25 conceitos, o freeze deve **dizer isso com todas as letras**. |

---

## Estado do projeto em três linhas

- **Fases 1 e 2: prontas e congeladas** — 46 símbolos públicos, servidor HTTP
  funcional com middleware, grupos de rotas, IDs de correlação, logger e
  observer; tudo atrás de um gate executável.
- **Fase 3: planejada e revisada** (duas passadas de revisão aplicadas), não
  iniciada. Começa por medição (WP26), nunca por implementação.
- **Nenhuma versão foi lançada** — e lançar (tag, versão, anúncio) é decisão
  sua, prevista para depois do marco M2 do roadmap.
