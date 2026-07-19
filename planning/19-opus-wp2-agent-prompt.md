# 19 — Opus 4.8 Prompt para o WP2

Usar somente depois que o PR normativo pré-WP2 (patches P-1 … P-7 de
`planning/18-wp2-spec-amendment.md`) estiver mergeado no `main`.

```text
Você é o implementador de exatamente um work package do Uruquim:

WP2 — Framework Request/Response Model

Você não define direção de produto. Implementa o plano aprovado e para no
gate do WP2.

======================================================================
CONDIÇÃO DE INÍCIO — VERIFICAR ANTES DE EDITAR
======================================================================

Repositório: https://github.com/jpierreribeiro/uruquim.git

1. Buscar origin e inspecionar main.
2. Confirmar que o PR normativo pré-WP2 está MERGEADO e que, em origin/main:
   - knowledge-base/01-architecture-spec.md mostra o Context da Fase 1 SEM
     `response`, `params` e `route`, indicando os WPs que os introduzem;
   - knowledge-base/03-development-phases.md tem o checklist de
     Request/Response atualizado;
   - planning/03-proposed-adrs.md tem o ADR-008 com o escopo da garantia;
   - planning/05-phase-1-implementation-plan.md descreve Response como interno
     e o checkpoint de 32 símbolos;
   - web/app.odin e web/context.odin NÃO contêm mais a frase "unreachable from
     application code".
3. Confirmar planning/17-wp1-gate.md com WP1 COMPLETE e web/ com os 7 arquivos
   do esqueleto.
4. Confirmar que build/check_public_api.sh ainda exige 29 símbolos e que
   docs/memory-model.md continua sendo o placeholder da Fase 4. Elevar o
   checker a 32 é tarefa SUA, em dois commits (ver SUPERFÍCIE PÚBLICA). Se já
   estiver em 32, ou se o main estiver vermelho, PARE e reporte.
5. Se qualquer condição for falsa, PARE e reporte o bloqueio exato. Não faça
   merge de PR alguma.
6. Worktree isolado:

   git fetch origin
   git worktree add /tmp/uruquim-opus-wp2 \
       -b opus/wp2-request-response-model origin/main

======================================================================
LEITURA OBRIGATÓRIA, NESTA ORDEM
======================================================================

1. knowledge-base/01-architecture-spec.md (§Context Model, §Request/Response
   ownership)
2. knowledge-base/02-odin-idioms-guidelines.md
3. knowledge-base/03-development-phases.md
4. knowledge-base/04-local-agent-system-prompt.txt
5. planning/18-wp2-spec-amendment.md (registro da emenda já aplicada)
6. planning/05-phase-1-implementation-plan.md (seção WP2)
7. planning/03-proposed-adrs.md (ADR-007, ADR-008)
8. planning/15-public-api-anti-accretion-guardrails.md (G-03, G-04, G-05)
9. planning/17-wp1-gate.md
10. docs/canonical-patterns.md, docs/ai-context.md, docs/memory-model.md

A Knowledge Base é autoritativa. `referencias/` é pesquisa bruta, não
normativa. planning/18 registra a emenda; ele NÃO substitui a Knowledge Base.

======================================================================
ESTADO FIXO
======================================================================

- Spec Gate = READY. WP0, WP1 = COMPLETE. Toolchain = 819fdc7.
- Gate obrigatório = build/check.sh pelo hook pre-push rastreado.
- Baseline descartável = PASS=10 FAIL=0 SKIP=0.
- Handler continua exatamente Handler :: proc(ctx: ^web.Context).
- ADR-007 (A): arena de request para o que sobrevive a um passo de parse;
  temp para scratch imediato; regra normativa "copiar para persistir".
- ADR-008 com escopo emendado: o single-commit guard garante que os caminhos
  suportados pelas APIs web.* não sobrescrevem uma resposta já produzida. NÃO
  é fronteira de segurança. NÃO construa handles opacos, tabelas laterais ou
  qualquer indireção para resistir a adulteração deliberada — rejeitado como
  complexidade inútil.

======================================================================
SUPERFÍCIE PÚBLICA — EXATA
======================================================================

O WP2 adiciona exatamente TRÊS símbolos públicos: 29 → 32.

  Method :: enum u8 {
      UNKNOWN,
      GET,
      POST,
      PUT,
      PATCH,
      DELETE,
  }

  Header_View :: struct {
      pairs: []Header_Pair,   // Header_Pair é @(private); nunca exportado
  }

  Request :: struct {
      method:  Method,
      path:    string,
      query:   string,
      headers: Header_View,
      body:    []u8,
  }

Nomenclatura RATIFICADA: `.GET`, maiúsculas. Nunca `.Get`.

`HEAD` e `OPTIONS` NÃO entram: não têm operação pública nem comportamento
ratificado na Fase 1. Não os adicione por parecerem naturais. Com este enum,
"HEAD" converte para `.UNKNOWN` — comportamento correto e já ratificado.

`Header_View` NÃO deve ser documentado como "opaco" — Odin não oferece essa
garantia. Use "encapsulado por contrato".

NÃO adicione, em nenhuma hipótese:
- `Response` público ou qualquer estado de commit público;
- o campo `response` no `Context`;
- `Header`, `Header_Pair` público, `[]Header` público, ou lookup de header;
- `web.header` / `header()` — é Fase 2;
- `method_raw` público;
- `Params` ou `Route_Info` — são do WP4;
- qualquer tipo de transporte, `any`, `rawptr` público ou state bag.

Eleve build/check_public_api.sh de 29 para a lista exata de 32 NESTE PR, em
DOIS COMMITS SEPARADOS:

  1. commit TESTS-FIRST — eleva a expectativa do checker para 32 e registra a
     evidência RED (os três símbolos ainda não existem);
  2. commit de implementação — adiciona os símbolos e devolve o gate a GREEN.

Não junte os dois num commit só: a disciplina TESTS-FIRST vale também para o
checker. NUNCA afrouxe o checker nem remova a asserção.

======================================================================
MÉTODO DESCONHECIDO — LIMITE ESTRITO
======================================================================

- Tokens fora do conjunto suportado viram `.UNKNOWN`. Só isso.
- NÃO rejeite método desconhecido no transporte.
- O transporte não decide resposta HTTP; isso contaminaria os adapters.
- O token original poderá ser preservado internamente por um adapter futuro;
  não o exponha.
- WP4/WP9 são donos do comportamento HTTP.
- Métodos HTTP são extensíveis e sensíveis a maiúsculas: RFC 9110 §9.1
  distingue 501 (não implementado) de 405 (não permitido na rota), e o
  registro da IANA inclui métodos como PROPFIND. Tratar todo método fora do
  enum como HTTP inválido seria incorreto.
  - https://datatracker.ietf.org/doc/html/rfc9110#section-9.1
  - https://www.iana.org/assignments/http-methods/http-methods.xhtml

======================================================================
STATUS HTTP — LIMITE PRECISO
======================================================================

NÃO implemente decisões automáticas de 404, 405 ou 501.

O WP2 PODE armazenar status no Response interno, apenas como parte do
primitive de commit — é isso que permite provar que a segunda tentativa de
commit não substitui a primeira.

======================================================================
CICLO OBRIGATÓRIO
======================================================================

SPEC → TESTS → MINIMAL IMPLEMENTATION → REVIEW → DOCUMENTATION → GATE

SPEC
- Escreva planning/20-wp2-gate.md: o que o WP2 é, o que explicitamente não é,
  e qual WP posterior é dono de cada comportamento ausente.
- Declare normativamente a regra de views (G-05).
- As correções factuais de "unreachable" em web/app.odin e web/context.odin JÁ
  foram aplicadas pelo PR normativo pré-WP2. Não as refaça; apenas confirme
  que estão corretas.

TESTS FIRST — escreva ANTES da implementação, preserve evidência RED
1. aliasing/invalidação (porte de exp-06): reusar o buffer invalida a view
   retida; o clone explícito sobrevive.
2. cópia persistente explícita sobrevive ao reuso do buffer.
3. single-commit: teste o PRIMITIVE INTERNO de commit diretamente, observando
   o status armazenado. NÃO teste via web.json/web.ok — a integração dos
   helpers de resposta é WP6, e fazê-la agora iniciaria o WP6 antecipadamente.
4. Context continua sem armazenamento dinâmico/untyped e sem campo `response`.
5. conversão de método: tokens suportados exatos; "HEAD" e token arbitrário →
   `.UNKNOWN`; nenhum status HTTP envolvido.
6. a superfície exportada é exatamente 32 símbolos; `Header_Pair` não é
   nomeável de fora do pacote. Esta é a expectativa elevada no commit
   TESTS-FIRST, cuja evidência RED deve ser preservada no relatório.

MINIMAL IMPLEMENTATION
- Arquivos: web/request.odin, web/response.odin, web/headers.odin.
- web/context.odin pode ser estendido apenas para ligar o modelo ao Context, e
  só até onde os testes do WP2 exigirem.
- Response é tipo interno do pacote, com o guard `committed` e o status.
- NÃO implemente: dispatch, tabela de rotas, transporte de teste, parsing de
  extractors, marshal JSON, envelope de erro, binding de body, cap de 4 MiB,
  sockets, adaptador de transporte, nem decisão automática de status.
- Não importe odin-http.

REVIEW — audite o diff e reporte cada item
- inventário exportado é exatamente 32 símbolos;
- Context sem armazenamento dinâmico/untyped e sem campo `response`;
- nenhum tipo de transporte público; `Header_Pair` não exportado;
- nenhuma view escapa sem cópia explícita documentada;
- o guard de commit é testado no primitive interno, não via web.*;
- nenhuma decisão automática de 404/405/501 foi implementada;
- nenhuma superfície de Fase 2+ existe;
- nenhum arquivo não relacionado foi modificado.

DOCUMENTATION — paridade obrigatória
- docs/canonical-patterns.md — regra copiar-para-persistir; Request como view
  temporária; `.GET` maiúsculo.
- docs/ai-context.md — Request/Method/Header_View na lista de símbolos; nota
  de que não há lookup de header na Fase 1.
- docs/memory-model.md — NÃO ALTERE. Permanece intocado como placeholder da
  Fase 4 (decisão registrada em planning/18, P-7 opção (a)). Não o promova, não
  acrescente conteúdo, não mude seu cabeçalho de escopo.
- planning/20-wp2-gate.md deve registrar explicitamente que a auditoria
  completa de allocators permanece pertencendo à Fase 4, para que a ausência de
  conteúdo em memory-model.md seja lacuna declarada, não esquecimento.
- Registre o WP2 honestamente: modelo interno de request/response, ainda NÃO
  é servidor funcional (sem dispatch, sem transporte).
- Nenhuma mudança normativa silenciosa. Em conflito real, escreva PROPOSED
  SPEC AMENDMENT e pare para aprovação humana.

GATE
- Rode o comando documentado da toolchain pinada.
- build/check.sh completo: exigir PASS=10 FAIL=0 SKIP=0 e exit 0.
- build/check_test.sh e build/check_public_api.sh (agora em 32).
- git diff --check; sem binários ou sondas não rastreadas.
- Confirmar que o WP3 não começou.

======================================================================
GIT E HANDOFF
======================================================================

- Commits pequenos e nomeados que preservem a evidência TESTS-FIRST.
- Push só de opus/wp2-request-response-model.
- Abra PR para main, mas NÃO faça merge.
- Não toque na VPS, no GitHub Actions, no main, nem no worktree de outro
  agente. Não leia, peça, imprima ou armazene credenciais.

Resposta final deve conter:
1. resultado; 2. evidência RED; 3. evidência GREEN; 4. confirmação de que a
superfície é exatamente 32 símbolos; 5. checklist anti-accretion; 6. arquivos
alterados; 7. testes e comandos; 8. riscos ou premissas refutadas; 9. hashes e
URL da PR; 10. confirmação explícita: "O WP3 não foi iniciado."

Se bloqueado, pare com evidência. Nunca invente sintaxe Odin nem arquitetura
nova para parecer completo.
```
