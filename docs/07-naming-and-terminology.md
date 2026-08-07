# 用語と命名 — 2026 年時点の正式名称

Microsoft の AI 関連製品は 2024-2026 年にかけて大きく改名されました。
古い記事やコードサンプルを読むとき、また社内で説明するときの対応表です。

---

## 製品名の変遷

| 旧称 | **現行（2026 年）** | 備考 |
|---|---|---|
| Azure AI Studio → Azure AI Foundry | **Microsoft Foundry** | 「Azure」が取れ、Microsoft ブランドに |
| Azure AI Services | **Foundry Tools** | Speech / Vision / Language 等の総称 |
| Azure OpenAI Service | Microsoft Foundry Models（の一部） | エンドポイントは互換維持 |
| Hub + Azure OpenAI + AI Services（3 リソース） | **Foundry resource**（単一） + projects | リソースモデルが簡素化 |
| Assistants API | **Responses API**（Agents v2） | API 設計が刷新 |
| Prompt Flow | Foundry の評価・トレース機能に統合 | — |
| Semantic Kernel / AutoGen | **Microsoft Agent Framework** | 両者の後継として統合 |

> ⚠️ ドキュメント URL は `learn.microsoft.com/azure/ai-foundry/...` のまま残っているものが多く、
> 製品名とパスが一致しないことがあります。

---

## API オブジェクトの変遷

Assistants API（旧）から Responses API（新）へのマッピング。

| 旧（Assistants API） | **新（Responses API）** |
|---|---|
| Thread | **Conversation** |
| Message | **Item** |
| Run | **Response** |
| Assistant | **Agent Version** |
| Run Step | Response の内部イベント |

**コード上の違い（概念）:**

```python
# 旧: Assistants API
thread = client.beta.threads.create()
client.beta.threads.messages.create(thread_id=thread.id, role="user", content="...")
run = client.beta.threads.runs.create(thread_id=thread.id, assistant_id=asst.id)

# 新: Responses API
response = client.responses.create(
    model="gpt-5",
    input="...",
    conversation=conversation_id,   # 状態は conversation で管理
)
```

---

## SDK の変遷

| 旧 | **現行** |
|---|---|
| `azure-ai-inference` | **`azure-ai-projects` 2.x** |
| `azure-ai-generative` | **`azure-ai-projects` 2.x** |
| `openai`（Azure 向け設定） | `openai`（そのまま利用可、`AzureOpenAI` クラス） |
| `semantic-kernel` / `autogen` | **`agent-framework`** |

### インストール

```bash
# Python
pip install azure-ai-projects openai azure-identity
pip install agent-framework          # Microsoft Agent Framework

# .NET
dotnet add package Azure.AI.Projects
dotnet add package Microsoft.Agents.AI.Foundry --prerelease
```

```bash
# Go（public preview）
go get github.com/microsoft/agent-framework-go
```

---

## RBAC ロールの変遷

| 旧称 | **現行** | 権限の範囲 |
|---|---|---|
| Azure AI Developer | **Foundry User** | モデル・エージェントの利用 |
| Azure AI Owner | **Foundry Owner** | プロジェクトの完全管理 |
| Cognitive Services Contributor | **Foundry Account Owner** | アカウント全体の管理 |
| （新設） | **Foundry Project Manager** | プロジェクト内のリソース管理 |

> データプレーンのロール（`Cognitive Services OpenAI User` 等）は別系統で残っています。

---

## Landing Zone まわりの用語

| 用語 | 意味 |
|---|---|
| **ALZ**（Azure Landing Zone） | Azure 全体の基盤。ネットワーク、ID、ガバナンス、監視の 8 設計領域 |
| **AILZ**（AI Landing Zone） | ALZ の上に載る AI 固有の基盤 |
| **Platform Landing Zone** | ALZ のうち、共有サービス（接続・ID・管理）を持つサブスクリプション群 |
| **Application Landing Zone** | ワークロードが載るサブスクリプション |
| **Foundry Landing Zone** | AILZ の 1 つ。エージェント開発・実行の環境 |
| **AI Gateway Landing Zone** | AILZ の 1 つ。全社共通の AI アクセス統制層（APIM ベース） |
| **standalone** | AILZ を単独で立てるモード（既存 ALZ なし） |
| **ailz-integrated** | 既存 ALZ に統合するモード |
| **greenfield / brownfield** | 新規構築 / 既存環境への追加 |
| **BYO**（Bring Your Own） | 既存リソース（VNet、DNS、Cosmos 等）を持ち込むこと |

> ⚠️ 元資料のスライドには "Support Platform Landing Zone" という第 3 のブロックが登場しますが、
> 公式リポジトリで実装が提供されている Landing Zone は
> **Foundry Landing Zone** と **AI Gateway Landing Zone** の 2 つです。
> Support Platform は ALZ の platform landing zone に相当する概念として理解してください。

---

## Foundry の内部コンポーネント

| 名称 | 説明 | 状態 |
|---|---|---|
| **Foundry resource** | アカウント本体。モデルデプロイとプロジェクトを持つ | GA |
| **Foundry project** | チーム・用途単位の分離境界 | GA |
| **Foundry Agent Service** | エージェントの実行基盤（オーケストレーション + 状態管理） | GA |
| **Foundry Models** | モデルカタログとデプロイ | GA |
| **Foundry Tools** | Speech / Vision / Language 等 | GA |
| **Foundry IQ** | 知識検索機能（Azure AI Search ベース） | ⚠️ 注記あり（下記） |
| **Microsoft Agent Framework** | マルチエージェントのオーケストレーション SDK | GA（Go は preview） |
| **Entra Agent ID** | エージェント固有の Entra ID | GA |

---

## Preview / 注意が必要な機能

本番投入前に GA 状態を確認してください。

| 機能 | 状態（2026 年時点） | 備考 |
|---|---|---|
| Agent Service の **memory** ツール | ⚠️ preview | 長期記憶 |
| Agent Service の **web search** ツール | ⚠️ preview | Grounding with Bing とは別 |
| **A2A**（Agent-to-Agent）プロトコル | ⚠️ preview | エージェント間通信のオープン標準 |
| Agent Framework **Go SDK** | ⚠️ public preview | Python / .NET は GA |
| Responses API の一部機能 | 一部 preview | API バージョンで異なる |

### 独立した製品ページが確認できない用語

以下はスライドや資料に登場しますが、**独立した公式製品ドキュメントが確認できていません**。
社内・社外の説明で使う際は注意してください。

| 用語 | 状況 |
|---|---|
| **Foundry IQ** | アクセラレータ内の機能名として実装されている（`RETRIEVAL_BACKEND=foundry_iq`）。Azure AI Search ベース。API バージョン `2026-05-01-preview`。独立した製品ページは未確認 |
| **Microsoft Agent 365** | スライドに登場するが、公式ドキュメントで確認できず |
| **Foundry Local** | スライドに登場するが、公式ドキュメントで確認できず |

> これらを顧客説明で使う場合は、「アクセラレータ内の機能名」「発表段階」等の
> 位置づけを明示することを推奨します。

---

## API バージョン

| 用途 | バージョン |
|---|---|
| Azure OpenAI（Chat Completions 等） | `2025-04-01-preview` 以降 |
| モデルデプロイ（ARM） | `2025-12-01-preview` |
| Foundry IQ（Search データプレーン） | `2026-05-01-preview` |

> API バージョンは頻繁に更新されます。
> 最新は https://learn.microsoft.com/azure/ai-foundry/openai/reference を確認してください。

---

## モデルのデプロイタイプ

| 名称 | 説明 |
|---|---|
| **GlobalStandard** | グローバルにルーティング。最も安価、最高スループット |
| **DataZoneStandard** | データゾーン（EU / US）内でルーティング |
| **Standard** | 単一リージョン固定 |
| **GlobalProvisionedManaged** | 専有スループット（グローバル） |
| **ProvisionedManaged (PTU)** | 専有スループット（リージョン固定） |
| **GlobalBatch** | バッチ処理向け（50% 割引、24 時間以内） |

---

## Bicep パラメータで使われる略語

`main.parameters.json` を読むときの手がかり。

| 略語 | 意味 |
|---|---|
| `AAF` | Azure AI Foundry |
| `ACA` | Azure Container Apps |
| `ACR` | Azure Container Registry |
| `AILZ` | AI Landing Zone |
| `CAF` | Cloud Adoption Framework |
| `CAPP` | Container App |
| `COGSVCS` | Cognitive Services |
| `MCP` | Model Context Protocol |
| `ODSOPSINSIGHTS` | `privatelink.ods.opinsights.azure.com`（Log Analytics） |
| `OMSOPSINSIGHTS` | `privatelink.oms.opinsights.azure.com`（Log Analytics） |
| `PE` | Private Endpoint |
| `PSQL` | PostgreSQL |
| `UAI` | User-Assigned Identity |
| `WS` | Workspace |
| `ZT` | Zero Trust |

---

## Private DNS Zone の対応表

`EXISTING_PRIVATE_DNS_ZONE_<KEY>_RESOURCE_ID` の `<KEY>` と実際のゾーン名。

| KEY | Private DNS Zone |
|---|---|
| `ACR` | `privatelink.azurecr.io` |
| `AISERVICES` | `privatelink.services.ai.azure.com` |
| `APPCONFIG` | `privatelink.azconfig.io` |
| `APPINSIGHTS` | `privatelink.applicationinsights.azure.com` |
| `AZUREAUTOMATION` | `privatelink.azure-automation.net` |
| `AZUREMONITOR` | `privatelink.monitor.azure.com` |
| `BLOB` | `privatelink.blob.core.windows.net` |
| `COGSVCS` | `privatelink.cognitiveservices.azure.com` |
| `CONTAINERAPPS` | `privatelink.<region>.azurecontainerapps.io` |
| `COSMOS` | `privatelink.documents.azure.com` |
| `KEYVAULT` | `privatelink.vaultcore.azure.net` |
| `ODSOPSINSIGHTS` | `privatelink.ods.opinsights.azure.com` |
| `OMSOPSINSIGHTS` | `privatelink.oms.opinsights.azure.com` |
| `OPENAI` | `privatelink.openai.azure.com` |
| `SEARCH` | `privatelink.search.windows.net` |

---

## 日本語表記のゆれ

社内文書で統一する際の推奨。

| 推奨 | 避ける |
|---|---|
| ランディングゾーン | ランディング・ゾーン、着地帯 |
| エージェント | エイジェント |
| プライベートエンドポイント | 私設エンドポイント |
| マネージド ID | 管理対象 ID |
| ガードレール | 防護柵 |
| グラウンディング | 接地、根拠付け |
| トークン | 字句 |
| 推論 | インファレンス |
| 埋め込み | エンベディング（文脈により併記） |

> 製品名（Microsoft Foundry、Azure Container Apps 等）は**英語表記のまま**を推奨します。

---

## 参考

- [なぜ Microsoft Foundry なのか](02-why-microsoft-foundry.md)
- [デプロイガイド](06-deployment-guide.md) — パラメータの実際の使い方
- Microsoft Foundry ドキュメント: https://learn.microsoft.com/azure/ai-foundry/
- Microsoft Agent Framework: https://learn.microsoft.com/agent-framework/
- Azure Landing Zones: https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/
