# 18 — PROPOSED SPEC AMENDMENT (WP2: Request/Response na Fase 1)

Status: **PROPOSTA APLICADA NESTA BRANCH, PENDENTE DE APROVAÇÃO HUMANA.** Só se
torna normativa após o merge da PR #3. Toolchain `dev-2026-07-nightly:819fdc7`;
base `origin/main` em `6ecd8b3`.

**Este documento não é autoritativo sobre a Knowledge Base.** Os patches P-1 …
P-7 abaixo já estão aplicados **nas próprias fontes normativas** nesta branch —
este documento é o registro da emenda, não a sua fonte de autoridade. A
hierarquia do projeto permanece: Knowledge Base > ADRs > planning. O WP2 só
pode iniciar depois que a PR #3 estiver mergeada.

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
	private: Header_View_Internal,
}

@(private)
Header_View_Internal :: struct {
	pairs: []Header_Pair,
}

@(private)
Header_Pair :: struct { name: string, value: string }

Request :: struct {
	method:  Method,
	path:    string,
	query:   string,
	headers: Header_View,
	body:    []u8,
}
```

`Header_View` **não anuncia** `pairs`. Expor `pairs: []Header_Pair` diretamente
congelaria na API pública justamente a representação por pares que o wrapper
existe para esconder por contrato. Com o slot aninhado, `Header_View` não
promete formato algum, e qualquer acesso à representação é deliberadamente não
canônico. Isso **não** cria símbolo público adicional nem segurança fictícia:
`r.headers.private.pairs` continua compilando (`exit=0`), como esperado.

`HEAD` e `OPTIONS` **não entram na Fase 1**: não têm operação pública nem
comportamento ratificado. Entram quando seu contrato for especificado e
testado. Com o enum mínimo, `HEAD` converte para `.UNKNOWN` — provado abaixo.

Superfície após o WP2: **exatamente 32** = 29 atuais + `Request` + `Method` +
`Header_View`. `Header_View_Internal` e `Header_Pair` são privados. Não há
lookup público de header.

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
| 9 | `Header_View` com slot aninhado: externo lê `Request` | `exit=0` | RATIFICADO |
| 10 | `Header_View_Internal` não nomeável de fora | `'Header_View_Internal' is not exported by 'web'` | RATIFICADO |
| 11 | Encapsulamento é por contrato, não barreira | `r.headers.private.pairs` compila (`exit=0`) | RATIFICADO |

Os itens 3–5 foram medidos na forma anterior (`pairs` direto); a mudança para o
slot aninhado é de visibilidade do campo, não de representação, e os itens 9–11
confirmam a forma final.

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

**Motivação.** Omitir `ctx.response` mantém a API responder-only: não anuncia
estado mutável de resposta como API pública, então a aplicação usa os helpers
em vez de editar status ou `committed` na mão, e o duplo-write acidental deixa
de ser um erro fácil de cometer.

**Não** torna o estado interno inacessível e **não** é fronteira de segurança —
formular assim seria repetir o erro factual que P-5/P-6 corrigem.

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

**Texto atual** — DUAS afirmações falsas no mesmo comentário

```odin
// Context_Internal is package-private and unreachable from application code.
// WP2 and WP4 give it real contents; in WP1 it exists only so that Context has
// a stable shape with no public field.
```

"unreachable" é falso (sonda A). "no public field" também é: `Context` tem o
campo `private`, que é público e alcançável — é exatamente por ele que o bypass
passa.

**Texto proposto**

```odin
// Context_Internal is package-private: application code cannot NAME this type.
// It is encapsulated BY CONTRACT, not by the compiler — Odin has no per-field
// privacy, and fields stay reachable through a public field. Do not rely on
// this for safety guarantees (ADR-008, "Scope of the guarantee").
// WP2 and WP4 give it real contents; WP1 contains only the contract-internal
// slot. Request data is introduced by WP2.
```

**Motivação.** Ambas as frases atuais são factualmente falsas.

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
Portanto o PR pré-WP2 **adiciona**, não corrige.

**Divisão decidida — o inventário positivo NÃO entra neste PR.** Documentar
`Request`, `Method` e `Header_View` como símbolos disponíveis enquanto eles
ainda não existem em `web/` tornaria a documentação falsa para qualquer agente
que a consultasse. Vale o mesmo princípio da sequência do checker: a asserção
anda junto com o código.

Entra **neste PR** (regras que já são verdadeiras hoje):

- `docs/canonical-patterns.md` — seção "Request data lifetime (copy to
  persist)": views temporárias, cópia explícita para persistir, trabalho em
  background nunca recebe view nem `ctx`, e a ausência de `ctx.response`.
- `docs/ai-context.md` — regras negativas: não existe `ctx.response`; dados de
  request são views temporárias; não há lookup de header na Fase 1
  (`web.header` é Fase 2).

Entra **no PR do WP2**, junto com os símbolos:

- inventário positivo de `Request`, `Method` e `Header_View` em
  `docs/ai-context.md`;
- exemplo com `.GET` maiúsculo em `docs/canonical-patterns.md`.

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
5. Só então o WP2 podia iniciar.
6. O PR do WP2, em commits separados: TESTS-FIRST eleva o checker a 32 e
   registra RED; a implementação adiciona os três símbolos e devolve GREEN.
7. O WP2 cria `planning/20-wp2-gate.md`, que registra que a auditoria completa
   de allocators permanece na Fase 4.
