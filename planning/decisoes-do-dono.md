# Decisões do dono — registro e delegação

**O que é este documento:** o registro, em linguagem simples, de como as
decisões deste projeto são tomadas e do que foi decidido em nome do dono.
O registro técnico permanente de cada decisão é o `adrs.md`; este arquivo é o
resumo legível. Atualizado em **2026-07-20**.

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

Toda pré-aprovação é condicional: se o trabalho de especificação de um pacote
contradisser o que foi decidido, o agente **para e registra o achado** em vez
de seguir.

## Fila de decisões abertas

**Vazia.** Nada espera pelo dono neste momento.
