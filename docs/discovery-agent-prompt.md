Esta é a execução autônoma da rotina diária de descoberta complementar de vagas. Não continue a implementação
nem a revisão da conversa anterior. Não invoque pair e não crie subagents.

Autorização: pesquisa pública na web e ingestão somente de vagas verificadas. Não altere código, perfis,
fontes, configurações, agendamentos, infraestrutura ou mensagens. Não se candidate a vagas e não crie contas,
credenciais ou serviços pagos.

Nunca imprima, registre ou repasse tokens, cabeçalhos de autorização, cookies ou URLs assinadas.

1. Política primeiro. Antes de qualquer busca ou POST, faça GET em
https://web-production-b2243.up.railway.app/api/v1/codex_fallback_sources com o cabeçalho Authorization:
Bearer. Use o valor da variável de ambiente INGEST_SHARED_TOKEN; se ela não existir, use o conteúdo do arquivo
tmp/.ingest_shared_token na raiz do projeto. Use timeout de conexão de 12 segundos e timeout de leitura de 95
segundos. Faça no máximo uma nova tentativa para falha transitória de rede ou timeout nesse GET. Nunca repita
401 ou 403: trate-os como bloqueio.

2. Se o GET falhar, retornar 401 ou 403, ou se a resposta não tiver policy.profiles e ingestion_endpoint, pare
e registre NÃO VERIFICADO. Não use perfis históricos. Não envie POST vazio e não registre zero vagas.

3. Avalie todos os perfis ativos de policy.profiles. Agrupe perfis equivalentes para a pesquisa, sem remover
nenhum perfil: a classificação final é do backend. Priorize Ruby/Rails, React e React Native, e mantenha
cobertura dos demais perfis ativos.

4. Orçamento: use até 30 consultas na rodada inicial, distribuídas entre os grupos. Se for útil, expanda até
60 consultas no total. Não tente executar todas as consultas retornadas. Registre em run.budget o limite
realmente usado e liste em run.gaps os grupos que ficaram sem cobertura.

5. Antes de escolher o orçamento, remova consultas duplicadas e rotacione a lista, mesmo quando ela vier em
ordem fixa legada. Não afirme que a busca usa o Google, a menos que o motor de busca seja conhecido.

6. Recência: se coverage.last_successful_codex_run existir com finished_at válido, calcule os dias desde
finished_at, arredonde para cima, limite entre 1 e 7 e use esse valor como janela de recuperação. Registre
window_start como o limiar real e window_label como "Nd", substituindo N pelo número de dias (ex.: "2d").
Se coverage ou last_successful_codex_run estiver
ausente ou nulo, use a janela legada de 24 horas e window_label "24h". Dê prioridade a vagas publicadas nas
últimas 24 horas. Não invente datas: se a data de publicação for desconhecida, registre-a como desconhecida.

7. Boards conhecidos: use coverage.native_sources como guia para explorar empresas novas. Pule apenas um board
individual que tenha evidência de verificação recente, registrada na sua própria evidência. A lista
known_boards sozinha não prova verificação recente. Nunca pule um ATS inteiro. Não contorne desafios de
acesso.

8. Para cada candidata, abra a página original. Confirme que a vaga está ativa e pode ser candidatada
diretamente. Verifique proveniência, data, elegibilidade geográfica, senioridade, idioma e exclusões. Se a
página não puder ser acessada, registre como lacuna e não marque a fonte como verificada.

9. Desduplique as URLs antes do envio e preserve a identidade da fonte original.

10. Envie as vagas verificadas por POST para o endpoint de ingestão indicado na política, resolvendo caminhos
relativos contra https://web-production-b2243.up.railway.app e usando o mesmo Bearer do GET e Content-Type
application/json. Use o formato aceito no README local: run e os arrays strong_matches, borderline_matches
e rejections. Cada vaga precisa de title, company e apply_url; preserve source_url, source_name/source_slug,
location_text, remote_signal, published_at e recency_text quando observados, sem inventar valores.
O objeto run deve conter: client_run_id, estável para este lote e gerado uma única vez;
started_at em ISO 8601; window_label; trigger_source igual a codex_automation; discovery_method igual a
luna_web_search; queries_executed como inteiro; hosts_checked como inteiro, contando apenas hosts realmente
abertos e sem repetição; source_slugs como array de strings, apenas com fontes realmente verificadas; gaps
como array de strings; budget como inteiro; window_start em ISO 8601. Nunca invente datas de verificação.

11. Se o primeiro POST der timeout ou falha de rede depois do envio, pare com status PENDENTE. Não faça retry
automático, mesmo que o contrato novo esteja ativo. Retry só manual, nunca nesta execução; quando houver,
reenvia exatamente o mesmo corpo, o mesmo endpoint e o mesmo Content-Type.

12. Interprete a resposta:
- 201 sem o campo replayed: recibo legado de sucesso. Registre search_run_id e contadores. Esse recibo não tem
  idempotência por execução; nunca o reenvie.
- 201 com replayed false: execução nova criada com este client_run_id. Registre search_run_id e contadores.
- 200 com replayed true: replay da mesma client_run_id com o mesmo corpo. Registre o recibo original e não
  trate como execução nova.
- 409 com client_run_id_conflict: a mesma client_run_id já foi usada com outro corpo. Pare, não altere o corpo
  sob essa chave e registre o conflito.
- 422 ou outro erro de validação: registre o erro e não reenvie automaticamente.
- 5xx, resposta sem corpo JSON ou qualquer status não listado acima: status PENDENTE, registre o status e
  não reenvie.
- A presença de coverage não prova idempotência.
- Se todas as buscas estiverem bloqueadas, não envie POST de sucesso vazio.
- Resultado parcial continua parcial, mesmo com 201.
- last_successful_codex_run não prova cobertura completa.

13. Evidência: salve em /tmp/codex-job-search-runs/<run_id>/, em que run_id é o horário UTC da execução.
Inclua a política atual, as consultas, as páginas abertas, a cobertura, as datas originais, as candidatas, as
lacunas, os bytes exatos do payload e o recibo. Não salve credenciais, cabeçalhos de autorização nem URLs
assinadas.

14. Relatório final em português e conciso: status FEITO, PENDENTE ou NÃO VERIFICADO; contadores reais;
search_run_id; lacunas. Dado indisponível não é zero vagas.
