# 26 — PROPOSED SPEC AMENDMENT (WP3: teardown cost eliminável)

Status: **PROPOSTA APLICADA NESTA BRANCH, PENDENTE DE APROVAÇÃO HUMANA.** Só se
torna normativa após o merge desta PR. Toolchain `dev-2026-07-nightly:819fdc7`;
base `origin/main` em `2972346`.

**Este documento não é autoritativo sobre a Knowledge Base.** Os patches P-1 e
P-2 abaixo já estão aplicados nas fontes normativas (`planning/21`,
`planning/15`) nesta branch. A hierarquia permanece: Knowledge Base > ADRs >
planning.

Resolve o único item aberto do WP3 (PR #9, READY_WITH_BLOCKER): o custo de
**+~5 KiB** de teardown que todo binário de aplicação passaria a carregar, mesmo
sem chamar `test_request`.

---

## PARTE I — Contexto e decisão

O WP3 (PR #9) entregou a fachada `web.test_request` e a maquinaria em
`web/testing`, com o gate verde e `core:testing` totalmente fora dos binários de
aplicação (0 símbolos). Restou **um** custo medido: `web.destroy` chama
incondicionalmente a rotina de teardown da maquinaria para liberar o recorder
App-owned, e essa aresta estática linka `recorder_destroy` + instanciações
`delete_*` em **todo** binário — **+5232 B** no relatório do agente, **+5264 B**
na minha remedição independente (ruído de source). O agente corretamente parou
em READY_WITH_BLOCKER e escalou o custo para decisão humana.

Você aprovou prototipar a eliminação por **registro lazy de teardown** (ponteiro
de procedimento setado só dentro de `test_request`), em código descartável, sem
tocar na implementação nem na spec durante o experimento; medir binário sem/com
`test_request`, símbolos via `nm` e custo/runtime; e, se o DCE eliminar o
suporte no app comum e o desenho ficar simples, propor a emenda antes de
implementar.

**Decisão ratificada:** adotar o registro lazy de teardown. `web.destroy` deixa
de referenciar estaticamente a rotina de teardown; o primeiro `test_request`
registra um ponteiro de procedimento privado no state do App, e `web.destroy` só
o invoca se registrado. Em binários que nunca chamam `test_request`, o linker
elimina `test_request` e, com ele, todo o teardown da maquinaria. O requisito de
custo ~zero passa a ser **verificado por `nm` no gate** (G-11), não apenas
medido e revisado.

Isto **não muda** a API pública (`test_request`, `Recorded_Response{status,
body}`) nem o contrato de lifetime (storage App-owned, lazy no primeiro
`test_request`, válido até `web.destroy`, liberado uma vez). É refinamento do
mecanismo interno + um novo check de gate — compatível com a planning/21.

## PARTE II — Evidência (protótipo descartável, fora do repositório)

Dois variantes idênticos exceto na fiação do `destroy`, compilados na toolchain
pinada com `-o:minimal`, `-collection:uruquim=<proto>`:

- **A** = design atual do WP3: `web.destroy` referencia `recorder_destroy`
  estaticamente.
- **B** = registro lazy: `web.destroy` chama um ponteiro de procedimento que só
  `test_request` atribui.

Baseline "sem a feature" (App puro, sem test-support): **42648 B**.

| Binário (app que **não** chama `test_request`) | Tamanho | Δ vs baseline | Símbolos de teardown (`nm`) |
|---|---|---|---|
| A — aresta estática | 47576 B | **+4928** | `recorder_destroy`, `delete_dynamic_array`, `delete_slice`, `delete_string` (4) |
| B — registro lazy | 42952 B | **+304** | **0** |

- Economia do B: **4624 B**. O residual +304 B é o `App` 8 bytes maior (o campo
  de ponteiro) + init, **não** a maquinaria de teardown.
- Em ambos, `test_request` já é dead-code-eliminated no app sem uso (`nm`: 0).
  A única diferença é a aresta de `web.destroy` → teardown.
- **Equivalência comportamental:** A e B imprimem `None ` (status zero, body
  vazio — a resposta uncommitted honesta do WP3 sem router).
- **Sem leak:** app B com duas chamadas `test_request` acumuladas, sob
  `mem.Tracking_Allocator`: `leaked=0 bad_frees=0` após `web.destroy`.
- **Simplicidade:** um campo `proc(a: ^App)` privado no state do App, um thunk
  privado, e a atribuição no primeiro `test_request`. Sem `rawptr`, `any`,
  ciclo, ou duplicação de tipo. Runtime: um nil-check + uma chamada indireta no
  destroy, só quando registrado.

Conclusão: o DCE elimina 100% do suporte de teardown no app comum e o desenho
permanece simples. Condição da Parte I satisfeita.

## PARTE III — PATCHES NORMATIVOS EXATOS

### P-1 — `planning/21-wp3-spec-amendment.md` · §Lifetime de `Recorded_Response`

Acrescenta à lista de lifetime o bullet do teardown lazy: `web.destroy` não
referencia estaticamente o teardown da maquinaria; o registro é lazy via
ponteiro privado; custo ~zero em binários que não testam; verificado por `nm` no
gate. Não altera a API nem os demais bullets. Ver o diff aplicado nesta branch.

**Motivação.** A planning/21 fixou o lifetime App-owned mas não o mecanismo de
teardown; o mecanismo estático custava ~5 KiB por binário. O registro lazy
preserva o contrato e elimina o custo.

**Evidência.** Parte II.

**Impacto.** Requisito interno + check de gate; nenhuma mudança pública.

### P-2 — `planning/15-public-api-anti-accretion-guardrails.md` · G-11

Fortalece o parágrafo de custo: de "meça e trate custo não-explicado como item
de revisão humana" para "o teardown DEVE ser eliminável pelo linker (registro
lazy); o gate afirma por `nm` zero símbolos de teardown de `web/testing` num app
que não testa; o único residual permitido é o campo de ponteiro no `App`".

**Motivação.** A disciplina anti-custo do projeto (a lição dos +41 KiB do
`core:testing`) aplica-se igualmente ao teardown: utilitário de teste não taxa
binário de aplicação. Com o registro lazy o custo é eliminável, então passa de
"revisar" para "eliminar e afirmar".

**Evidência.** Parte II.

**Impacto.** O gate do WP3 ganha uma asserção baseada em `nm`. Ver Parte IV.

## PARTE IV — Sequência de aplicação

1. Você aprova esta emenda (merge desta PR).
2. A implementação do WP3 (branch `opus/wp3-test-transport`, PR #9) é revisada
   para o **variant B**: `web.destroy` chama o teardown via ponteiro privado
   registrado no primeiro `test_request`. O `Recorded_Response`, a maquinaria e
   o contrato de lifetime não mudam.
3. O gate do WP3 (`build/check.sh` / `build/check_public_api.sh` /
   `planning/23-wp3-gate.md`) ganha a asserção `nm`: um app mínimo que não chama
   `test_request` linka **zero** símbolos de teardown de `web/testing`. A
   medição de tamanho vira check, não item de revisão.
4. Com o custo eliminado e afirmado, o WP3 sai de READY_WITH_BLOCKER para
   COMPLETE. O agente abre/atualiza o PR; **o merge é decisão humana**.

Esta emenda é normativa apenas após o merge. A implementação do variant B só
começa depois disso (o protótipo desta Parte II é evidência de viabilidade, não
a ratificação permanente — essa vive nos probes versionados do WP3).
