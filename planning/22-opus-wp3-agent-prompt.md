# 22 — Opus 4.8 Prompt para o WP3

Usar somente depois que a PR #5 (`planning/21-wp3-spec-amendment.md`) estiver
mergeada no `main`. Este prompt delega exatamente WP3; não autoriza WP4.

```text
Você é o implementador de exatamente um work package do Uruquim:

WP3 — In-memory Test Transport

Você não define direção de produto. Implementa o plano humano aceito, registra
evidência real e para no gate do WP3. Não faça merge da própria PR.

======================================================================
CONDIÇÃO DE INÍCIO — VERIFICAR ANTES DE EDITAR
======================================================================

Repositório: https://github.com/jpierreribeiro/uruquim.git

1. Execute `git fetch origin` e inspecione `origin/main`.
2. Confirme que a PR #5 está MERGEADA e que `origin/main` contém o commit
   `2943d3e` ou um descendente com:
   - `planning/21-wp3-spec-amendment.md` em status HUMAN-ACCEPTED / MERGED;
   - `planning/05-phase-1-implementation-plan.md` descrevendo a fachada
     `web.test_request` e a maquinaria em `web/testing`;
   - `planning/15-public-api-anti-accretion-guardrails.md` com G-11;
   - `planning/20-wp2-gate.md` registrando WP2 concluído;
   - superfície pública atual exatamente 32 símbolos;
   - nenhum `web/test_support.odin` e nenhum `web/testing/` ainda.
3. Rode `bash build/check.sh`. A baseline obrigatória é:
   - exit 0;
   - protótipos `PASS=10 FAIL=0 SKIP=0`;
   - WP1/WP2 verdes;
   - checker de API em exatamente 32 símbolos.
4. Meça e registre, ANTES de implementar, o tamanho de um executável mínimo
   que importa `uruquim:web`, cria/destroi App e NÃO chama `test_request`.
   Registre comando, tamanho, toolchain e commit em `planning/23-wp3-gate.md`.
5. Se qualquer condição for falsa, PARE e reporte o bloqueio exato.
6. Crie worktree isolada:

   git worktree add /tmp/uruquim-opus-wp3 \
       -b opus/wp3-test-transport origin/main

Todo o trabalho ocorre somente nessa worktree.

======================================================================
LEITURA OBRIGATÓRIA, NESTA ORDEM
======================================================================

Leia integralmente:

1. knowledge-base/01-architecture-spec.md
2. knowledge-base/02-odin-idioms-guidelines.md
3. knowledge-base/03-development-phases.md
4. knowledge-base/04-local-agent-system-prompt.txt
5. planning/21-wp3-spec-amendment.md
6. planning/05-phase-1-implementation-plan.md — WP3 e dependências
7. planning/15-public-api-anti-accretion-guardrails.md — G-01…G-11
8. planning/20-wp2-gate.md
9. planning/03-proposed-adrs.md — ADR-007, ADR-008, ADR-009, ADR-011
10. planning/06-risk-register.md — R-04, R-10, R-11, R-14
11. docs/canonical-patterns.md — Testing
12. docs/ai-context.md e docs/quick-start.md
13. experiments/08-transport-boundary e experiments/09-test-transport
14. build/check.sh e build/check_public_api.sh
15. web/app.odin, context.odin, request.odin, response.odin, headers.odin

A Knowledge Base continua autoritativa. `referencias/` é pesquisa não
normativa. O protótipo externo registrado em planning/21 é evidência de
viabilidade; os probes versionados deste WP são a ratificação permanente.

======================================================================
ESTADO FIXO E LIMITES
======================================================================

- Spec Gate da Fase 1 = READY.
- WP0, WP1 e WP2 = COMPLETE.
- Toolchain = `dev-2026-07-nightly:819fdc7`.
- Gate obrigatório = `bash build/check.sh` e hook pre-push.
- GitHub Actions não está disponível; gate local + repetição VPS são a
  autoridade operacional.
- Handler permanece exatamente `Handler :: proc(ctx: ^Context)`.
- Nenhum tipo de transporte pode aparecer na API pública.
- Nenhum `any`, `rawptr`, `map[string]any`, state bag ou `core:testing` em
  código de produção.
- `web/testing` não importa `uruquim:web`; a dependência é unidirecional.
- Não implemente routing, params, handlers reais, extractors, JSON, 404, 405,
  middleware, sockets, adapter, conformance WP9 ou qualquer parte do WP4+.
- Não altere a Knowledge Base. Se ela realmente impedir o WP3, PARE e proponha
  emenda; não resolva silenciosamente.
- Não modifique `docs/memory-model.md`; continua placeholder da Fase 4.
- Não altere `experiments/` para transformar protótipos em produto.

======================================================================
SUPERFÍCIE PÚBLICA EXATA
======================================================================

O WP3 adiciona exatamente DOIS símbolos públicos ao pacote `web`:

    Recorded_Response :: struct {
        status: Status,
        body:   string,
    }

    test_request :: proc(
        a:      ^App,
        method: Method,
        path:   string,
    ) -> Recorded_Response

Ledger após WP3:

    Application API:  32 (não muda)
    Test-support API:  2  (Recorded_Response, test_request)
    União em web:      34

Decisões obrigatórias:

- `Recorded_Response` expõe somente `status` e `body` nesta fase.
- NÃO adicione `headers`, `committed`, allocator, transport, cleanup ou outro
  campo público.
- O recorder interno captura/copia headers para os testes internos futuros do
  WP4, mas não existe ainda uma abstração pública ratificada para consultar
  headers de resposta. O 405+Allow será testado internamente no WP4.
- `body` é uma string view sobre uma cópia possuída pelo test-support state do
  App; não aponta para o buffer encerrado da requisição.
- `status` é copiado por valor.
- Duas respostas retornadas por chamadas consecutivas permanecem legíveis até
  `web.destroy(&app)`; destroy libera todas as cópias exatamente uma vez.
- Não existe cleanup público de Recorded_Response.
- O state é lazy: uma aplicação que não chama test_request não aloca recorder.
- `web/testing` é maquinaria interna por contrato. Quaisquer declarações que
  precisem ser visíveis entre packages são inventariadas e minimizadas no
  gate; não são uma segunda API canônica e não são documentadas para consumo.

======================================================================
DIVISÃO DE RESPONSABILIDADES
======================================================================

Arquivos previstos:

    web/test_support.odin              package web: os 2 exports públicos
    web/testing/test_transport.odin    package testing: fluxo in-memory
    web/testing/recorder.odin          cópias possuídas e cleanup
    web/testing/request_builder.odin   records neutros, sem tipos web

O fluxo permitido é:

    web.test_request
        → constrói request neutra/in-memory
        → fachada web converte para Request/Context
        → chama o stub privado de dispatch pertencente ao core
        → recorder recebe o Response interno
        → copia status/body/headers para o state do App
        → fachada retorna Recorded_Response{status, body}

WP3 NÃO possui router. Portanto:

- o stub privado de dispatch permanece sem routing e sem resposta automática;
- NÃO produza um 200/echo falso só para deixar o teste bonito;
- NÃO implemente 404/405 antecipadamente;
- o teste público prova forma, ausência de socket e integração estrutural;
- os testes de cópia/lifetime usam responses neutras/canned no nível interno;
- WP4 substitui/completa o dispatch e passa a provar rotas reais usando a
  mesma `web.test_request`.

Não mova Request, Response, Context, Status ou App para outro package. Não
duplique esses tipos em duas representações públicas. Records neutros privados
da fronteira são permitidos apenas na maquinaria e devem ser mínimos.

Se a direção `web → web/testing` exigir ciclo, rawptr, any, duplicação de tipos
públicos ou um conjunto amplo de bridge exports, PARE. Produza um protótipo
descartável em `/tmp`, registre compilador/comando/diagnóstico e peça decisão;
não improvise outra arquitetura dentro do PR.

======================================================================
CICLO OBRIGATÓRIO DO WP3
======================================================================

Siga exatamente:

SPEC → TESTS → MINIMAL IMPLEMENTATION → REVIEW → DOCUMENTATION → GATE

Mantenha commits semanticamente separados. No mínimo:

1. `WP3 SPEC/TESTS FIRST` — RED real e preservado.
2. `WP3 MINIMAL IMPLEMENTATION` — GREEN.
3. `WP3 DOCUMENTATION/GATE` — paridade, evidências e conclusão.

Não reescreva o commit RED depois de obter GREEN.

======================================================================
TESTS FIRST — OBRIGATÓRIO
======================================================================

Antes de criar qualquer arquivo de produção do WP3:

1. Crie/atualize os contratos para esperar:
   - `web/test_support.odin`;
   - somente `Recorded_Response` e `test_request` no ledger test-support;
   - application ledger ainda exatamente 32;
   - união exatamente 34;
   - somente `web/testing/` permitido como novo subdiretório;
   - nenhum outro subdiretório liberado;
   - `test_request` removido da lista Phase-2+;
   - `Response` continua proibido como export.
2. Faça o checker falhar em RED porque arquivos/símbolos ainda não existem.
   Preserve saída e exit code em `planning/23-wp3-gate.md`.
3. Adicione contrato externo compilável para a assinatura e os dois campos de
   Recorded_Response. Adicione probe negativo para um campo `headers` público.
4. Porte C1–C5 de planning/21 para probes versionados:
   - package machinery compila sem importar web;
   - package web compila importando machinery;
   - `core:testing` não aparece em produção;
   - callsite externo de web.test_request compila e roda sem socket;
   - fixture de back-edge falha com diagnóstico esperado de import cycle.
5. Testes internos, executados em throwaway package como no WP2:
   - request builder preserva method/path durante a chamada síncrona;
   - recorder copia body: mutar/reusar a origem não altera a cópia;
   - recorder copia header names/values internamente;
   - duas respostas consecutivas continuam legíveis;
   - destroy libera toda memória rastreada uma vez;
   - state permanece não alocado antes do primeiro test_request;
   - nenhum socket/porta/syscall de rede existe no caminho.
6. Checker/mutation tests:
   - símbolo extra no ledger de aplicação falha;
   - símbolo extra no ledger test-support falha;
   - subdiretório diferente de web/testing falha;
   - import de core:testing em produção falha;
   - import web dentro de web/testing falha;
   - declaração `@(init)` em test-support/machinery falha.
7. Registre a baseline do binário mínimo, já medida antes da implementação.

Os testes de produção não ficam dentro de `web/` e não linkam `core:testing`
em aplicações. Reuse o padrão de throwaway package do WP2.

======================================================================
IMPLEMENTAÇÃO MÍNIMA
======================================================================

- Adicione apenas os quatro arquivos previstos, salvo se um arquivo de teste
  ou probe externo for necessário.
- Acrescente ao App somente o state privado tipado necessário ao recorder.
- Inicialização do state deve ser zero/lazy; nenhum `@(init)`.
- `app()` e `bare()` continuam sem alocação.
- `destroy(&app)` limpa o state se inicializado e permanece no-op para apps que
  nunca usaram test_request.
- Request path/method são views válidas apenas durante a chamada síncrona.
- Response body/headers são copiados antes do Context/request storage acabar.
- Use allocator explícito e ownership verificável. Não use temp_allocator para
  dados devolvidos por Recorded_Response.
- Não exponha rawptr, any, maps, handles de backend ou tipos da machinery.
- Não adicione aliases, builders públicos, overloads ou argumentos opcionais.
- Não aceite query/body/headers no test_request público desta fase.
- Não use reflection, codegen, CLI ou build tags para esconder o pacote.
- Não crie uma ABI de Transport; o boundary interno continua conceitual e
  unfrozen sob ADR-009.

Declarações mecanicamente exportadas pelo package `web/testing` para permitir
a chamada cross-package são unsupported internals. Minimize-as, liste-as em
planning/23 e faça o checker travar a lista exata para evitar crescimento
silencioso. Não as inclua nos 34 exports do package `web`.

======================================================================
REVIEW DE CUSTO OCULTO — BLOQUEIO REAL
======================================================================

Depois do GREEN, recompile o mesmo app mínimo que NÃO chama test_request:

- mesma toolchain, flags e fonte da baseline;
- registre tamanho antes/depois e delta;
- confirme ausência de `core:testing`;
- confirme ausência de `@(init)` e alocação de test-support em app()/bare();
- compile também um app que chama test_request para provar que o linker inclui
  a maquinaria quando usada.

Não invente um threshold aceitável. Se o binário sem uso tiver delta não nulo:

1. determine e registre a causa;
2. não altere a API nem mova packages unilateralmente;
3. marque o gate `READY_WITH_BLOCKER` e peça decisão humana sobre o custo.

Se o delta for zero, registre a evidência. Se for não zero mas explicado, a
aceitação continua sendo humana; o agente não marca WP3 COMPLETE sozinho.

======================================================================
DOCUMENTAÇÃO
======================================================================

No mesmo PR, depois do GREEN:

- `docs/canonical-patterns.md`: seção Testing com assinatura real, campos
  status/body, lifetime até destroy, ausência de sockets e nota de que routing
  funcional chega no WP4.
- `docs/ai-context.md`: inventário separado Application (32) / Testing (2),
  forma canônica e proibições de inventar `testing.test_request`, headers,
  cleanup ou builders.
- `docs/quick-start.md`: somente corrigir afirmações que ficariam falsas;
  não prometer uma rota funcional antes do WP4.
- `planning/23-wp3-gate.md`: SPEC, RED, GREEN, review, mutation tests, memória,
  lista de internals do package testing, tamanho binário e status final.
- Não altere docs/memory-model.md nem documentos de Fase 2+.

Todos os exemplos adicionados precisam compilar na toolchain pinada.

======================================================================
CRITÉRIOS DE CONCLUSÃO
======================================================================

WP3 só pode ser COMPLETE quando:

- build/check.sh exit 0;
- baseline descartável permanece PASS=10 FAIL=0 SKIP=0;
- WP1/WP2 continuam verdes;
- 32 application + 2 test-support = 34, sem extras;
- C1–C5 existem como probes versionados e passam/falham como esperado;
- test_request compila/roda sem socket e sem implementar routing;
- recorder copia body/headers e duas respostas sobrevivem até destroy;
- memory tracker mostra cleanup completo;
- nenhum core:testing ou test file entra no package entregue;
- nenhum init/alocação ocorre quando test_request não é usado;
- custo binário sem uso foi medido e, se não nulo, aceito por humano;
- docs e ai-context correspondem exatamente ao código;
- nenhum símbolo/feature de WP4+ entrou;
- git diff --check limpo e worktree sem artefatos.

Se o custo binário aguarda decisão humana, use `READY_WITH_BLOCKER`, não
COMPLETE. Se a arquitetura de packages falhar, use BLOCKED e apresente o
protótipo/diagnóstico. Não enfraqueça o gate para obter verde.

======================================================================
ENTREGA
======================================================================

1. Faça review final do diff inteiro.
2. Rode o gate completo e mutation checks.
3. Abra PR contra main; NÃO faça merge.
4. Não inicie WP4.
5. Relate:
   - commits SPEC/RED, implementação/GREEN e docs/gate;
   - saída do gate;
   - superfície 32+2=34;
   - arquivos alterados;
   - lista exata de bridge exports internos em web/testing;
   - lifetime/cleanup provados;
   - tamanho do binário antes/depois e causa do delta;
   - desvios, blockers e decisões humanas necessárias;
   - URL da PR;
   - confirmação explícita: "WP4 não foi iniciado."
```
