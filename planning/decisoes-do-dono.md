# Decisões do dono — registro e delegação

**O que é este documento:** o registro, em linguagem simples, de como as
decisões deste projeto são tomadas e do que foi decidido em nome do dono.
O registro técnico permanente de cada decisão é o `adrs.md`; este arquivo é o
resumo legível. Atualizado em **2026-07-21**.

---

## A missão, e como ela decide

> *A web framework for the Joy of Programming.*

Em 2026-07-20 o dono definiu essa linha — que já era a do README — como o
critério do projeto, e delegou as decisões pendentes e as aprovações futuras
ao agente executor. O **ADR-029** registra o regime completo. Em resumo:

1. **Disciplina primeiro.** Medição decide performance; na dúvida de
   segurança, desconfiar; os guardrails e os ledgers nunca são atropelados.
2. **Joy em segundo.** Quando a disciplina não decide, vence a opção que torna
   escrever um programa mais agradável: menos conceitos, diagnóstico na hora
   do registro/boot (nunca às 3h da manhã), menos cerimônia.
3. **Conveniência por último.** "Joy" nunca justifica crescer a API pública —
   isso continua exigindo evidência (G-09).

Na dúvida entre duas opções, vale a **mais fácil de desfazer**.

## O que continua parando no dono (sempre)

- Lançar qualquer versão, tag ou release.
- Mudar a licença (`LICENSE`).
- Mudar a própria missão.
- Tornar Tina uma dependência, ou commitar `tina/`.
- Reescrever histórico já publicado no git.
- Qualquer coisa que o agente julgue difícil de reverter **e** incerta.

Para revogar ou ajustar a delegação, basta dizer — uma frase em qualquer
sessão resolve.

---

## Decisões já tomadas sob a delegação (2026-07-20)

| Decisão | O que ficou decidido, em uma linha |
|---|---|
| **ADR-028** — estado por requisição | **Não existe.** O "porteiro" valida e o valor é passado adiante como parâmetro comum; o custo de revalidação é aceito e documentado. Reabre só com um programa real, medido neste repositório, que não consiga ser escrito de forma limpa. |
| **ADR-010** — API avançada | Fica desenhada, **não lançada**, até um usuário externo real pedir. Nunca aparece no Quick Start. |
| **ADR-013** — proxies confiáveis | Por padrão, vale o endereço da conexão; confiar em proxy é configuração explícita do operador. Detalhes de API ficam para a Fase 4. |
| **CI no GitHub** | **Continua sem CI** — o gate roda local/VPS, decisão reconfirmada pelo dono em 2026-07-20. |
| **Fase 3, todas as aprovações** | Resolvidas de antemão no plano (§2b do `phase-3-plan.md`): diagnóstico de conflito com poison (WP30); nenhuma normalização de caminho, permanente, params crus (WP31a); HEAD e OPTIONS automáticos, sem 501 (WP32a); acessor de rota aprovado (WP34); limites configuráveis com runtime derivado no boot e registro-durante-serving rejeitado (WP36); WP37 só implementa o ADR-004; o freeze (WP38) é aprovado pelo próprio gate — e qualquer violação para e volta ao dono. |
| **Fase 4, escopo** — ⚠️ **parcialmente revertida em 2026-07-21, ver a tabela da Fase 5 abaixo** | Plano rascunhado (`phase-4-plan.md`, §2b): CORS, uploads e arquivos estáticos ficam **fora do núcleo** (pacotes opcionais futuros) — *esta parte foi revertida*; TLS é terminado no proxy reverso — esse é o jeito suportado de rodar; a decisão de concorrência fica **deliberadamente aberta** até haver protótipos e medição (ADR-030, procedimento já escrito). O rascunho é obrigatoriamente re-revisado contra os resultados da Fase 3 antes de começar. |

Toda pré-aprovação é condicional: se o trabalho de especificação de um pacote
contradisser o que foi decidido, o agente **para e registra o achado** em vez
de seguir.

---

## Decisões do dono (2026-07-21) — Fase 5

Estas cinco **revertem ou estreitam** algo já escrito. Estão aqui, e não só no
`adrs.md`, porque a cláusula de condicionalidade logo acima exige que uma
contradição do que foi decidido **pare e seja registrada** — nunca seguida em
silêncio. O registro técnico é o `planning/phase-5-spec.md` §1.

| Decisão | O que ficou decidido, em uma linha |
|---|---|
| **Mesa posta vai para o núcleo** | **Reverte a linha "Fase 4, escopo" da tabela acima.** CORS, uploads e arquivos estáticos entram em `web/`, com crescimento de ledger e pagando G-09 por inteiro. Um microframework sem os três não é um microframework, é uma biblioteca de rotas. **TLS, OpenAPI, WebSocket e streaming continuam fora** — a emenda nomeia três itens e nenhum outro. |
| **Critério "demand-driven" dispensado, só para esses três** | O roadmap exige "um pedido real de usuário" por item da Fase 5. Isso é insatisfazível com zero usuários: não há demanda sem gente, e não haverá gente sem as features que a demanda pediria. Dispensa-se a **espera pelo pedido**, nunca a evidência G-09. Não se estende a WebSocket, streaming, HTTP/2, OpenAPI, templates, banco de dados ou API avançada. |
| **`core:net/http` chega em janeiro de 2027** | A stdlib do Odin ganha um `net/http` oficial (esperado com limitações). Duas consequências: o braço C da ADR-033 (**possuir** a camada de conexão) fica economicamente morto, e **todo trabalho da Fase 5 ganha um segundo critério de aceitação — não dificultar a troca**. Os patches de drenagem no vendor são declaradamente **ponte descartável**. |
| **Camada tipo LiveView: adiada** | Avaliada e **recusada para agora**. Exigiria mexer na fronteira `Dispatch_Proc`/`Outbound` — justamente o que torna o framework agradável de escrever — e otimizava para uma ideia ainda não confirmada. A ideia não morreu; está fora da Fase 5. |
| **Portão CE-E4 abriu** | A ADR-032 condicionou trabalho de ecossistema a "depois do WP44". O WP44 mergeou em 2026-07-21 (PR #77). A condição está cumprida e **nenhum documento da árvore registrava isso**. Registrado. O CE-E3 continua intacto: nada da Fase 5 é trabalho de ecossistema. |

## Fila de decisões abertas

- **ADR-033 — a fundação de transporte.** Reaberta em 2026-07-21 pelo próprio
  gatilho que ela escreveu. Com o `core:net/http` datado, a recomendação passa a
  ser fechar em **manter e remendar, com a transição como saída declarada**. A
  decisão final volta ao dono no freeze da Fase 5 (WP65) se o patch de drenagem
  não ficar contido.
- **Lançar tag ou versão.** Continua parando no dono, como sempre. Nada a
  decidir hoje — o roadmap não permite tag antes do M2.
