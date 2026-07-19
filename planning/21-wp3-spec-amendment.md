# 21 — ACCEPTED SPEC AMENDMENT (WP3: test transport facade na Fase 1)

Status: **HUMAN-ACCEPTED / MERGED.** PR #5 mergeada em 2026-07-19 como
`2943d3e`. Toolchain `dev-2026-07-nightly:819fdc7`; base histórica da emenda
`origin/main` em `3e6292f`.

**Este documento não é autoritativo sobre a Knowledge Base.** Os patches P-1 e
P-2 abaixo já estão aplicados **nas próprias fontes normativas** (`planning/05`,
`planning/15`) nesta branch — este documento é o registro da emenda, não a sua
fonte de autoridade. A hierarquia do projeto permanece: Knowledge Base > ADRs >
planning. O WP3 só pode iniciar depois que esta PR estiver mergeada e o prompt
do agente (planning/22) estiver revisado.

Resolve os dois bloqueios registrados no handoff WP3:

- **Bloqueio 1** — `build/check_public_api.sh` proíbe subdiretórios em `web/`,
  mas o WP3 precisa de `web/testing/`.
- **Bloqueio 2** — `planning/05` põe os arquivos em `web/testing/`, enquanto a
  Knowledge Base, `docs/canonical-patterns.md:464` e `docs/quick-start.md:11`
  chamam `web.test_request` — símbolo do pacote `web`, não `web/testing`.

---

## PARTE I — Decisões humanas ratificadas

### Decisão 1 — `web.test_request` é a forma pública canônica

A forma normativa prevalece pela hierarquia do projeto. Cinco fontes já dizem
`web.test_request` (KB prosa, `docs/canonical-patterns.md`, `docs/quick-start.md`,
`planning/05` §API); só a *lista de arquivos* de `planning/05` (a fonte de menor
autoridade) sugeria `web/testing`. Portanto:

- `test_request` é exportado pelo pacote `web`;
- `Recorded_Response` também é exportado pelo pacote `web`;
- a maquinaria (transporte de teste, recorder, request builder) permanece em
  `web/testing`;
- `knowledge-base/01`, `docs/canonical-patterns.md` e `docs/quick-start.md`
  **não mudam**;
- `planning/05` é corrigido para distinguir **fachada pública** de
  **implementação** (P-1).

Semântica de pacote de Odin: um símbolo declarado em `web/testing/` só é
chamável como `testing.test_request`. Para ser `web.test_request`, a declaração
tem de viver no pacote `web` (diretório `web/`). Daí o layout:

```
web/
├── test_support.odin          # package web: test_request + Recorded_Response
└── testing/
    ├── test_transport.odin     # package testing: inbox/outbox sobre valores neutros
    ├── recorder.odin           # package testing: copia status/headers/body
    └── request_builder.odin     # package testing: monta a requisição canônica
```

**Restrição de dependência (obrigatória, sem ciclo).**

```
web (fachada pública)
        ↓
web/testing (maquinaria)
        ↓
boundary / modelos internos neutros
```

`web/testing` **não importa** `uruquim:web`. Opera sobre o boundary interno,
callbacks ou records neutros. A fachada pública converte `App`, `Method` e a
resposta capturada através da fronteira. Se isso não puder ser representado sem
ciclo ou duplicação de tipos, o agente do WP3 **para e produz um protótipo de
packages** — não move tipos nem introduz `rawptr` silenciosamente. É também
**proibido importar `core:testing`** na fachada ou na maquinaria: `web.test_request`
é uma utilidade de teste, mas não depende do test runner do Odin.

**Lifetime de `Recorded_Response`.** A resposta capturada não pode apontar para
o buffer já encerrado da requisição:

- `status` é copiado por valor;
- `body` e `headers` são copiados pelo recorder;
- o armazenamento pertence ao **test-support state do App**;
- é criado de forma lazy no primeiro `test_request`;
- permanece válido até `web.destroy(&app)`;
- nenhum cleanup público adicional é introduzido;
- aplicações que nunca usam `test_request` não alocam recorder.

Ergonomia preservada:

```odin
app := web.app()
defer web.destroy(&app)

res := web.test_request(&app, .GET, "/users/42")
testing.expect_value(t, res.status, .OK)
testing.expect_value(t, res.body, `{"id":42}`)
```

### Decisão 2 — dois ledgers de superfície

A linguagem verá **34 exports** totais; a governança distingue:

```
Application API:  32
Test-support API:  2   (Recorded_Response, test_request)
Total exportado:  34
```

"Ledger separado" **não** significa API menos séria: `test_request` e
`Recorded_Response` continuam públicos, documentados, compiláveis e protegidos
contra mudança acidental. O `build/check_public_api.sh` passa a fazer **três**
asserções (uma vez que o WP3 aterrisse):

1. ledger de aplicação exatamente 32;
2. ledger de test-support exatamente 2;
3. união exportada exatamente 34, sem símbolos extras.

A documentação deve apresentar: inventário da aplicação; seção separada
"Testing"; lifetime de `Recorded_Response`; ausência de sockets e portas;
nenhum tipo do transporte; nenhuma promessa de que `web/testing` seja
importável diretamente. Registrado como guardrail **G-11** (P-2).

---

## PARTE II — Evidência (protótipo de packages descartável, fora do repositório)

Um protótipo de packages descartável, compilado na toolchain pinada
(`dev-2026-07-nightly:819fdc7`, `-collection:uruquim=<proto>`), ratifica a forma
antes da produção. O protótipo vive **fora do repositório** (§3.6) e reproduz o
esqueleto `web` (fachada) + `web/testing` (maquinaria neutra) + consumidor
externo.

O protótipo externo é evidência de viabilidade, não o guard permanente. O
commit TESTS-FIRST do WP3 deve portar C1–C5 para probes executáveis e
versionados. A forma só é considerada ratificada pelo produto quando esses
probes rodam no gate normal; o agente não pode citar apenas esta tabela.

| # | Requisito | Evidência | Status |
|---|---|---|---|
| C1 | `web/testing` compila sozinho como maquinaria neutra | `odin check web/testing` `exit=0`; imports = só `core:strings` | RATIFICADO |
| C2 | Fachada `web` importa `web/testing` unidirecional | `odin check web` `exit=0`; import `uruquim:web/testing` | RATIFICADO |
| C3 | Nenhum `core:testing` na fachada nem na maquinaria | nenhuma linha `import "core:testing"` | RATIFICADO |
| C4 | Call-site externo `web.test_request(&app, .GET, "/users/42")` compila e roda, lendo `res.status`/`res.body` | `odin run` → `status=200 body=/users/42`, `exit=0` | RATIFICADO |
| C5 | A back-edge `web/testing → web` é ciclo de compilação | `odin check web` `exit=1`: `Cyclic importation of 'testing'` | RATIFICADO |

C5 é a prova de que a direção unidirecional é obrigatória, não apenas
preferida: o compilador rejeita o ciclo. C4 é a prova de que o lifetime
lazy/owned e a conversão neutro→`web.Recorded_Response` produzem exatamente a
ergonomia da Decisão 1.

---

## PARTE III — PATCHES NORMATIVOS EXATOS

### P-1 — `planning/05-phase-1-implementation-plan.md` · §WP3

**Texto atual (linhas de Files/API/Min impl)**

```
- **Files.** `web/testing/test_transport.odin`, `web/testing/recorder.odin`,
  `web/testing/request_builder.odin`.
- **API.** `web.test_request(&app, method, path) -> Recorded_Response`.
- **Tests first.** `test_request` round-trips a canned request (port exp-09
  harness).
- **Min impl.** inbox/outbox loop calling dispatch; recorder captures status/
  headers/body/commit.
```

**Texto proposto.** Distingue fachada pública (`web/test_support.odin`, package
`web`) de maquinaria (`web/testing`, package `testing`); fixa a direção de
dependência unidirecional e a cláusula "para e protótipa"; fixa o lifetime
owned/lazy de `Recorded_Response`; e move a elevação do checker para o commit
TESTS-FIRST do próprio WP3 (contrato dual-ledger). Ver o diff aplicado nesta
branch.

**Motivação.** A lista de arquivos original implicava `testing.test_request`,
contradizendo cinco fontes de maior autoridade. O desvio corrige a fonte de
menor autoridade em vez de reabrir a KB.

**Evidência.** Parte II (C1–C5).

**Impacto.** `planning/05` passa a descrever a forma real dos pacotes. Nenhuma
decisão de fase anterior é revertida. `web/testing/` e `web/internal/` já eram
declarados aditivos em `planning/05` §Global rollback.

### P-2 — `planning/15-public-api-anti-accretion-guardrails.md` · G-11 + mapa

**Texto atual.** Não há guardrail sobre superfície de test-support; o mapa de
enforcement não tem linha de WP3.

**Texto proposto.** Novo **G-11 — Test-support surface is a separate ledger**
(dois ledgers: 32 aplicação + 2 test-support = 34; três asserções do checker;
fachada em `web`, maquinaria em `web/testing` sem `uruquim:web` nem
`core:testing`; lifetime owned pelo App; documentação com seção "Testing"
separada) e uma linha de WP3 no mapa de enforcement.

**Motivação.** A decisão dos dois ledgers precisa de casa normativa em
`planning/15` (onde vive a política de superfície), não apenas neste registro.

**Evidência.** Partes I e II.

**Impacto.** `build/check_public_api.sh` ganhará a terceira asserção — **mas
essa alteração pertence ao PR do WP3, não a esta PR pré-WP3.** Elevar o checker
para o contrato dual-ledger antes de `web/test_support.odin` e `web/testing/`
existirem deixaria o `main` vermelho: o gate exige contagem exata e proíbe
subdiretórios em `web/`.

### Contrato futuro do checker (aplicado no PR do WP3, não aqui)

Registrado para que o agente do WP3 tenha alvo exato. No commit TESTS-FIRST do
WP3, `build/check_public_api.sh`:

1. permite o subdiretório `web/testing/` **especificamente** — não afrouxa a
   proibição geral de subdiretórios (linha ~169). `web/internal/` e outros
   permanecem fora do escopo até seus próprios WPs;
2. adiciona `test_support.odin` ao conjunto esperado de arquivos de `web/` e
   trata-o como o **ledger de test-support**: exatamente `Recorded_Response` e
   `test_request`;
3. mantém os demais `web/*.odin` no **ledger de aplicação**: exatamente 32;
4. afirma a união exportada = 34, sem extras;
5. **remove `test_request` da lista de símbolos de fase futura** (seção 3, hoje
   linha ~223) — `Response` continua proibido; `Recorded_Response` é permitido
   (o `grep -qx` casa nome exato, então `Response` não colide com
   `Recorded_Response`);
6. NÃO adiciona `*_test.odin` nem `core:testing` a `web/` (bans permanentes,
   seção 0), e NÃO lê `web/testing/` para a política de imports core/uruquim da
   seção 7 se isso reintroduzir falsos positivos — a maquinaria pode importar
   `core:` livremente.
7. executa os probes versionados equivalentes a C1–C5 e mede uma aplicação
   mínima que não chama `test_request`: nenhum init/alocação de test-support e
   delta de tamanho binário registrado para decisão humana se não for nulo ou
   claramente explicado.

Sequência, dentro do PR do WP3, em **commits separados**:

1. commit TESTS-FIRST — eleva o checker ao contrato dual-ledger e **registra
   RED** (os arquivos e símbolos ainda não existem);
2. commit de implementação — adiciona `web/test_support.odin` e `web/testing/*`
   e devolve o gate a **GREEN**.

---

## PARTE IV — Notas de não-mudança (decididas)

- **Knowledge Base intocada.** `knowledge-base/01` §Test transport já diz
  `web.test_request` (l. 960). O esboço de árvore em l. 1162
  (`testing/ — test_request, recorder`) descreve *onde a superfície de teste
  mora* em alto nível; a divisão fachada/maquinaria refina a localização física
  de cada símbolo **sem** mudar a forma pública que a prosa da KB manda. Não é
  contradição que exija patch — é decisão consciente (lição do §6: cheque a
  fonte antes de aceitar um desvio).
- **`docs/canonical-patterns.md` e `docs/quick-start.md` intocados.** Já usam
  `web.test_request`. O inventário positivo em `docs/ai-context.md` (a seção
  "Testing" separada) entra **junto com os símbolos, no PR do WP3** — documentar
  `test_request`/`Recorded_Response` como disponíveis enquanto não existem em
  `web/` tornaria a doc falsa para qualquer agente que a consultasse (mesmo
  princípio da sequência do checker no P-4 da emenda WP2).
- **`build/check_public_api.sh` intocado nesta PR.** Permanece verde em 32 e com
  a proibição de subdiretórios. A elevação é trabalho do WP3.

---

## PARTE V — Sequência de aplicação

1. Você aprova esta emenda explicitamente.
2. Esta PR pré-WP3 aplica P-1 e P-2 **nas fontes normativas** (`planning/05`,
   `planning/15`) e adiciona este registro (`planning/21`).
3. `build/check_public_api.sh` permanece em 32, subdiretórios proibidos;
   nenhuma doc pública e nenhuma fonte da KB muda.
4. Esta PR é revisada e mergeada; o gate completo deve continuar verde
   (contagem 32, subdiretórios proibidos).
5. Só então `planning/22-opus-wp3-agent-prompt.md` (revisado por humano) pode
   ser escrito e usado.
6. O PR do WP3, em commits separados: TESTS-FIRST eleva o checker ao contrato
   dual-ledger, porta C1–C5, adiciona os testes de duas respostas/lifetime e a
   medição do binário sem uso, e registra RED; a implementação adiciona a
   fachada e a maquinaria e devolve GREEN.
7. O WP3 cria `planning/23-wp3-gate.md`.

**Renumeração vs. handoff.** O handoff WP3 numerava o prompt como `planning/21`
e o gate como `planning/22`. Como esta emenda ocupa `planning/21` (espelhando a
emenda WP2 em `planning/18`), o prompt passa a `planning/22` e o gate a
`planning/23`.
