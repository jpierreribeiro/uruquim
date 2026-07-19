# 18 — PROPOSED SPEC AMENDMENT (WP2: Request/Response na Fase 1)

Status: **PROPOSTA. Requer aprovação humana.** Nada aplicado. Toolchain
`dev-2026-07-nightly:819fdc7`; `origin/main` em `6ecd8b3`.

**Este documento não é autoritativo sobre a Knowledge Base.** Ele propõe
patches exatos que, uma vez aprovados, devem ser aplicados **diretamente nas
fontes normativas** por um PR pré-WP2. A hierarquia do projeto permanece:
Knowledge Base > ADRs > planning. O WP2 só pode iniciar depois que esse PR
estiver mergeado.

---

## PARTE I — API exata proposta para a Fase 1

```odin
Method :: enum u8 {
	UNKNOWN,
	GET,
	POST,
	PUT,
	PATCH,
	DELETE,
}

// Encapsulado POR CONTRATO sobre a representação interna.
// Odin não oferece opacidade real; ver P-5/P-6.
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
```

`HEAD` e `OPTIONS` **não entram na Fase 1**: não têm operação pública nem
comportamento ratificado. Entram quando seu contrato for especificado e
testado. Com o enum mínimo, `HEAD` converte para `.UNKNOWN` — provado abaixo.

Superfície após o WP2: **exatamente 32** = 29 atuais + `Request` + `Method` +
`Header_View`. `Header_Pair` é privado. Não há lookup público de header.

## PARTE II — Evidência (protótipos descartáveis, nada no repositório)

| # | Requisito | Evidência | Status |
|---|---|---|---|
| 1 | `Header_View` usado dentro de `Request` | compila | RATIFICADO |
| 2 | Pacote externo lê `Request` | `exit=0`; `.GET` e `.UNKNOWN` comparam | RATIFICADO |
| 3 | Backing interno por views | pares apontam para o buffer | RATIFICADO |
| 4 | Invalidação após reuso | `"application/json"` → `"text/plain!!!!!!"` | RATIFICADO |
| 5 | Cópia persistente sobrevive | `strings.clone` → `"application/json"` | RATIFICADO |
| 6 | Ausência de `Header` público | `'Header_Pair' is not exported by 'web'` | RATIFICADO |
| 7 | Enum mínimo | `GET=GET HEAD=UNKNOWN PROPFIND=UNKNOWN` | RATIFICADO |
| 8 | Privacidade por campo em Odin | erro de sintaxe; 4 desenhos, nenhum estanque | RATIFICADO |

---

## PARTE III — PATCHES NORMATIVOS EXATOS

### P-1 — `knowledge-base/01-architecture-spec.md` · §Context Model · linha ~519

**Texto atual**

```odin
Context :: struct {
	request:  Request,
	response: Response,

	params: Params,
	route:  Route_Info,

	private: Context_Internal,   // chain cursor, allocators, transport hooks
}
```

**Texto proposto**

```odin
// Fase 1
Context :: struct {
	request: Request,            // WP2

	private: Context_Internal,   // chain cursor, allocators, transport hooks
}

// `response` NÃO é campo público. Aplicações respondem exclusivamente por
// web.json / web.ok / web.created / web.text / web.no_content e os helpers
// de erro. O Response interno e seu guard de commit pertencem ao WP2/WP6.
//
// `params: Params` e `route: Route_Info` são introduzidos pelo WP4 (routing).
```

**Motivação.** Expor `response` publicamente tornaria `ctx.response.committed`
alcançável pela aplicação, transformando o guard do ADR-008 em convenção
documental. Omitir o campo é a única forma coerente de manter o Response
interno sem prometer garantia que o compilador não dá.

**Evidência.** Sondas A/B/C/D: `@(private)` esconde o nome da declaração, não a
alcançabilidade de campos por meio de campo público. `@(private)` por campo de
struct é erro de sintaxe.

**Impacto.** Desvio consciente de struct normativa. Nenhum documento público
referencia `ctx.response`, `ctx.params` ou `ctx.route` hoje (verificado por
`git grep` em `docs/`), então o impacto em exemplos é nulo.

---

### P-2 — `knowledge-base/03-development-phases.md` · checklist · linha 123

**Texto atual**

```
- [ ] define `Request`/`Response` minimum fields, commit semantics, and the
      request-lifetime view rule (no retention without explicit copy)
```

**Texto proposto**

```
- [x] define `Request` public minimum fields (`method`, `path`, `query`,
      `headers`, `body`), the `Method` minimum set
      (`UNKNOWN/GET/POST/PUT/PATCH/DELETE`), and `Header_View` as a
      contract-encapsulated wrapper over private pairs — WP2
- [x] `Response` and its commit state stay internal; the single-commit guard
      covers the supported `web.*` paths and is not a security boundary — WP2
- [x] request-lifetime view rule: no retention without explicit copy — WP2
- [ ] `HEAD`/`OPTIONS` contracts — deferred until specified and tested
```

**Motivação.** O item único misturava decisões de fases diferentes e mantinha
`Response` como público por omissão.

**Evidência.** Partes I e II.

**Impacto.** Checklist do Spec Gate da Fase 1.

---

### P-3 — `planning/03-proposed-adrs.md` · ADR-008 · linhas 145–157

**Texto atual (trecho decisivo)**

```
- **Decision.** **A** for buffered responses; revisit for streaming
  (out of MVP). Onion-after must not mutate a committed response — ties to
  ADR-005/C.
```

**Texto proposto**

```
- **Decision.** **A** for buffered responses; revisit for streaming
  (out of MVP). Onion-after must not mutate a committed response — ties to
  ADR-005/C.
- **Scope of the guarantee (amended, WP2).** The guard ensures that the
  supported `web.*` response paths do not overwrite an already-produced
  response. It is NOT a security boundary against deliberate manipulation of
  framework internals: application and framework share one program. Odin's
  `@(private)` hides a declaration's name, not the reachability of fields
  through a public field, and per-field privacy is a syntax error. Designs
  that add indirection (opaque handles, side tables) to resist deliberate
  tampering are REJECTED as useless complexity.
```

**Motivação.** O ADR afirmava um guard sem delimitar o que ele garante. A
evidência mostra que a garantia forte é inalcançável em Odin.

**Evidência.** Sondas A–D e o erro de sintaxe de `@(private)` por campo.

**Impacto.** ADR-008 passa a ter escopo explícito. Nenhuma decisão anterior é
revertida.

---

### P-4 — `planning/05-phase-1-implementation-plan.md` · WP2 · linha de API

**Texto atual**

```
- **API.** `Request{method,path,query,headers,body}`, `Response{status,headers,
  body,committed}`.
```

**Texto proposto**

```
- **API.** Público: `Request{method,path,query,headers,body}`, `Method`,
  `Header_View`. Interno: `Response{status,headers,body,committed}` e
  `Header_Pair` — não exportados. Checkpoint de superfície após o WP2:
  exatamente 32 símbolos (29 + 3).
```

**Motivação.** A linha atual descreve `Response` como API do WP2.

**Evidência.** Parte I.

**Impacto.** `build/check_public_api.sh` passa de 29 para 32 na lista exata —
**mas essa alteração pertence ao PR do WP2, não ao PR normativo pré-WP2.**
Elevar o checker para 32 antes de `Request`/`Method`/`Header_View` existirem em
`web/` deixaria o `main` vermelho: o gate exige contagem exata.

Sequência decidida, dentro do PR do WP2, em **commits separados**:

1. commit TESTS-FIRST — eleva a expectativa do checker para 32 e **registra a
   evidência RED** (os três símbolos ainda não existem);
2. commit de implementação — adiciona `Request`, `Method` e `Header_View` e
   devolve o gate a **GREEN**.

Isso preserva a disciplina TESTS-FIRST no próprio checker, em vez de mover
código e asserção num commit só.

---

### P-5 — `web/context.odin` · comentário de `Context_Internal`

**Texto atual**

```odin
// Context_Internal is package-private and unreachable from application code.
```

**Texto proposto**

```odin
// Context_Internal is package-private: application code cannot NAME this type.
// It is encapsulated BY CONTRACT, not by the compiler — Odin has no per-field
// privacy, and fields remain reachable through a public field. Do not rely on
// this for safety guarantees (ADR-008, scope of the guarantee).
```

**Motivação.** A frase atual é factualmente falsa.

**Evidência.** Sonda A: `c.private.committed = true` compilou com `exit=0`,
enquanto nomear o tipo falhou com `'Internal' is not exported by 'pkg'`.

**Impacto.** Correção factual em código já mergeado.

---

### P-6 — `web/app.odin` · linha 18 · comentário de `App_Internal`

**Texto atual**

```odin
// App_Internal is package-private and unreachable from application code.
```

**Texto proposto** — idêntico a P-5, trocando `Context_Internal` por
`App_Internal`.

**Motivação/Evidência/Impacto.** Iguais a P-5. A mesma afirmação falsa aparece
em dois arquivos.

---

### P-7 — Documentação pública

`git grep` confirma que nenhum documento em `docs/` referencia `ctx.request`,
`ctx.response`, `ctx.params`, `ctx.route`, `Header_View` ou `Method` hoje.
Portanto o PR pré-WP2 **adiciona**, não corrige:

- `docs/canonical-patterns.md` — regra copiar-para-persistir; `Request` como
  view temporária; `.GET` maiúsculo.
- `docs/ai-context.md` — `Request`/`Method`/`Header_View` na lista de símbolos;
  nota de que não há lookup de header na Fase 1.

**`docs/memory-model.md` — DECIDIDO: permanece intocado.** O documento
declara-se *"Placeholder — written during Phase 4 after the allocator/lifetime
audit."* e continua assim. A regra de lifetime e de copiar-para-persistir entra
em `docs/canonical-patterns.md` e `docs/ai-context.md`, não ali.

`planning/20-wp2-gate.md` deve registrar explicitamente que **a auditoria
completa de allocators continua pertencendo à Fase 4** — para que a ausência de
conteúdo em `memory-model.md` seja lacuna declarada, não esquecimento.

---

## PARTE IV — Sequência de aplicação

1. Você aprova esta emenda explicitamente.
2. PR pré-WP2 aplica P-1, P-2, P-3, P-4, P-5, P-6 e P-7 **nas fontes
   normativas**. As correções factuais de `App_Internal`/`Context_Internal`
   entram aqui, não como trabalho incidental do implementador do WP2.
3. **`build/check_public_api.sh` permanece em 29 neste PR.** `docs/memory-model.md`
   permanece intocado.
4. PR pré-WP2 é revisado e mergeado; o gate completo deve continuar verde
   (PASS=10 FAIL=0 SKIP=0, contagem 29).
5. Só então `planning/19-opus-wp2-agent-prompt.md` pode ser usado.
6. O PR do WP2, em commits separados: TESTS-FIRST eleva o checker a 32 e
   registra RED; a implementação adiciona os três símbolos e devolve GREEN.
7. O WP2 cria `planning/20-wp2-gate.md`, que registra que a auditoria completa
   de allocators permanece na Fase 4.
