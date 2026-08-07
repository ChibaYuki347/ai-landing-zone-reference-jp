# リファレンスアーキテクチャ

AI Landing Zones は **2 つのリファレンスアーキテクチャ**を提供します。
どちらも Azure Landing Zone（プラットフォーム）の上に載る**ワークロード Landing Zone** です。

| Landing Zone | 目的 | 中核サービス | 典型的な配置 |
|---|---|---|---|
| **Foundry Landing Zone** | AI アプリケーション／エージェントの実行基盤 | Microsoft Foundry + Agent Service | AI Agent Prod Subscription |
| **AI Gateway Landing Zone** | 全社の AI エンドポイントを統制するガバナンスハブ | Azure API Management | AI Hub Prod Subscription |

> **両者の関係:** まず Foundry Landing Zone を展開してモデルとエージェントを配置し、
> その上に AI Gateway Landing Zone を重ねて全社ガバナンスを効かせる、というのが標準的な順序です。
> Gateway LZ は Foundry LZ 以外（AWS Bedrock、Google Gemini、他社 API）も配下に置けます。

---

## 全体の階層

```mermaid
flowchart TB
    subgraph UC["AI ユースケース層 (20%)"]
        A1["RAG チャット"]
        A2["文書処理"]
        A3["業務エージェント"]
    end

    subgraph AILZ["AI Landing Zone 層 (30%)"]
        direction LR
        FLZ["**Foundry Landing Zone**<br/>AI Agent Prod Subscription<br/>Foundry / Agent Service / Search /<br/>Cosmos / Container Apps"]
        GLZ["**AI Gateway Landing Zone**<br/>AI Hub Prod Subscription<br/>APIM / Content Safety /<br/>計測 / API Center"]
    end

    subgraph ALZ["Azure Landing Zone 層 (50%)"]
        direction LR
        CONN["Connectivity<br/>Hub VNet / Firewall / DNS / ExpressRoute"]
        IDENT["Identity<br/>Entra ID / Domain Services"]
        MGMT["Management<br/>Log Analytics / Automation"]
        GOV["Governance<br/>Azure Policy / Management Groups"]
    end

    ALZ --> AILZ --> UC
    GLZ -.統制.-> FLZ
```

---

## 1. Foundry Landing Zone

![Foundry Landing Zone](images/foundry-landing-zone.png)

> 元資料スライド 35 より。

### 1.1 論理構成

```mermaid
flowchart TB
    subgraph SUB["AI Agent Prod Subscription / AI Agent Resource Group"]
        subgraph VNET["AI Services VNet (spoke)"]
            subgraph SN1["Private Endpoints subnet"]
                PE["Private Endpoint × 12<br/>各 PaaS への閉域接続"]
            end
            subgraph SN2["Foundry Agent subnet (委任)"]
                AGT["Agent 実行<br/>ネットワーク注入"]
            end
            subgraph SN3["Application Gateway subnet"]
                AGW["Application Gateway<br/>+ WAF"]
            end
            subgraph SN4["Container App Environment subnet"]
                CAE["Container Apps Environment<br/>(Dapr)"]
            end
            subgraph SN5["Jump box subnet"]
                JB["Jumpbox VM"]
                BAS["Azure Bastion"]
            end
            subgraph SN6["Build agent subnet"]
                BA["ACR Task Agent Pool<br/>ビルドエージェント"]
            end
            UDR["UDR → hub firewall<br/>すべての送信を FW 経由に強制"]
        end

        subgraph FDRY["Microsoft Foundry"]
            ACC["Foundry Account<br/>(旧 Hub 相当)"]
            PRJ["Foundry Project<br/>AI Services endpoints /<br/>Foundry models /<br/>Connections / Agents"]
        end

        subgraph AGSVC["Foundry Agent Service standard setup"]
            ST1["Storage Account<br/>ファイル"]
            SR1["AI Search<br/>ベクトル索引"]
            CS1["Cosmos DB<br/>スレッド／実行状態<br/>(≧3000 RU/s)"]
            KV1["Key Vault<br/>シークレット"]
        end

        subgraph KNOW["知識ソース"]
            BING["Grounding with Bing"]
            SRCH["AI Search Service"]
        end

        subgraph APPDEP["GenAI アプリ依存リソース"]
            CDB["Cosmos DB"]
            KV2["Key Vault"]
            SA["Storage Account"]
            ACR["Container Registry"]
            APPCFG["App Configuration"]
        end

        subgraph MS["GenAI アプリ マイクロサービス (Container Apps)"]
            FE["Frontend"]
            ORC["Orchestrator"]
            MCPS["MCP Server"]
            ING["Ingestion"]
        end

        subgraph MON["監視"]
            DS["Diagnostic Settings"]
            NW["Network Watcher"]
            AI2["Application Insights"]
            LAW["Log Analytics"]
        end
    end

    AGW --> CAE
    CAE --> PRJ
    PRJ --> AGSVC
    PRJ --> KNOW
    CAE --> APPDEP
    VNET -.Private Endpoint.-> FDRY
    MON -.収集.-> SUB
```

### 1.2 主要な設計判断

| 設計領域 | 判断 | 理由 |
|---|---|---|
| **ネットワーク** | すべての PaaS を Private Endpoint 化、パブリックアクセス無効 | 規制要件・データ流出防止 |
| **送信制御** | UDR で全送信を hub の Azure Firewall へ強制 | エージェントの外部通信を監査可能に |
| **エージェント実行** | Foundry Agent subnet へ**ネットワーク注入** | エージェントの実行自体を VNet 内に閉じる |
| **状態管理** | Agent Service の依存を BYO（自テナントの Cosmos/Storage/Search/KV） | データレジデンシ、既存バックアップ運用の適用 |
| **アプリ実行** | Container Apps Environment（Dapr 有効） | マイクロサービス間通信、サービスディスカバリ、状態管理 |
| **入口** | Application Gateway + WAF | L7 保護、TLS 終端、OWASP ルール |
| **運用アクセス** | Bastion + Jumpbox（パブリック IP なし） | 閉域環境の運用手段 |
| **CI/CD** | Build agent subnet に ACR Task Agent Pool | 閉域内でのコンテナビルド |
| **DNS** | Private DNS Zone 15 種（既存 Zone の BYO 可） | hub 集中管理と整合 |

### 1.3 必要な Private DNS Zone（15 種）

| # | ゾーン | 対象サービス |
|---|---|---|
| 1 | `privatelink.cognitiveservices.azure.com` | Cognitive Services |
| 2 | `privatelink.openai.azure.com` | Azure OpenAI |
| 3 | `privatelink.services.ai.azure.com` | Foundry (AI Services) |
| 4 | `privatelink.search.windows.net` | AI Search |
| 5 | `privatelink.documents.azure.com` | Cosmos DB |
| 6 | `privatelink.blob.core.windows.net` | Storage (Blob) |
| 7 | `privatelink.vaultcore.azure.net` | Key Vault |
| 8 | `privatelink.azconfig.io` | App Configuration |
| 9 | `privatelink.<region>.azurecontainerapps.io` | Container Apps |
| 10 | `privatelink.azurecr.io` | Container Registry |
| 11 | `privatelink.monitor.azure.com` | Azure Monitor |
| 12 | `privatelink.oms.opinsights.azure.com` | Log Analytics (OMS) |
| 13 | `privatelink.ods.opinsights.azure.com` | Log Analytics (ODS) |
| 14 | `privatelink.agentsvc.azure-automation.net` | Agent Service |
| 15 | `privatelink.applicationinsights.azure.com` | Application Insights |

> Azure Landing Zone の connectivity サブスクリプションで DNS を集中管理している場合は、
> `existingPrivateDnsZone*` パラメータで既存ゾーンを参照できます（[デプロイガイド](06-deployment-guide.md)参照）。

### 1.4 Agent Service の Cosmos DB コンテナ

Foundry Agent Service（standard setup）は以下のコンテナを作成します。

| ランタイム | コンテナ |
|---|---|
| Classic | `thread-message-store`, `system-thread-message-store`, `agent-entity-store` |
| New runtime | `agent-definitions-v1`, `run-state-v1` |

> **注意:** アカウント全体で **最低 3,000 RU/s** が必要です。小規模検証でも一定のコストが発生します。

---

## 2. AI Gateway Landing Zone

![AI Gateway Landing Zone](images/ai-gateway-landing-zone.png)

> 元資料スライド 35 より。

### 2.1 論理構成

```mermaid
flowchart TB
    subgraph SUB["AI Hub Prod Subscription / AI Hub Resource Group"]
        subgraph VNET["AI Hub VNet (region 1 spoke, DNS は hub 提供)"]
            subgraph SN1["API Management subnet"]
                APIM["**Azure API Management**<br/>AI Hub - Region 1 Stamp<br/>← AI ゲートウェイの中核"]
            end
            subgraph SN2["Private Endpoints subnet"]
                PE["Private Endpoints"]
            end
            subgraph SN3["Microsoft Foundry Agent subnet"]
                FA["Foundry Agent"]
            end
            subgraph SN4["Logic App subnet"]
                LA["Logic Apps"]
            end
            UDR["UDR → hub firewall"]
        end

        subgraph FDRY["Microsoft Foundry Service (オプション)"]
            MI["Managed Identities"]
            CONN["Connections"]
            FM["Foundry models"]
        end

        subgraph SAFE["Pluggable Safety Services"]
            PII["Language Service<br/>PII 検出・マスキング"]
            CSAF["Content Safety<br/>有害コンテンツ・ジェイルブレイク検出"]
        end

        subgraph GOVSVC["Governance Supporting Services"]
            EH["Event Hub<br/>利用ストリーム"]
            CDB["Cosmos DB<br/>利用実績・課金計測"]
            KV["Key Vault<br/>サブスクリプションキー"]
            SA["Storage Account"]
            REDIS["Managed Redis<br/>セマンティックキャッシュ"]
        end

        subgraph WF["Gov Workflows / AI Registry"]
            LAPP["Logic Apps<br/>使用量取り込み"]
            APIC["**API Center**<br/>Universal AI Registry"]
        end

        subgraph MON["監視"]
            DS["Diagnostic Settings"]
            AL["Alerts"]
            AI2["Application Insights"]
            LAW["Log Analytics"]
        end

        subgraph SEC["セキュリティ・ガバナンス"]
            DEF["Microsoft Defender"]
            ENT["Microsoft Entra ID"]
            PUR["Microsoft Purview"]
        end
    end

    Apps["業務アプリ / エージェント"] --> APIM
    APIM --> SAFE
    APIM --> FDRY
    APIM -->|"外部プロバイダ"| EXT["AWS Bedrock<br/>Google Gemini<br/>任意の外部 API"]
    APIM --> EH --> LAPP --> CDB
    APIM --> REDIS
    APIC -.カタログ.-> APIM
    SEC -.横断.-> SUB
```

### 2.2 APIM が解く 5 つの課題

| 課題 | APIM での解決 | 実装 |
|---|---|---|
| **モデルスプロール** | 全モデルを単一のフロントドアに集約 | Universal LLM API / Azure OpenAI 互換 API |
| **コスト帰属不能** | サブスクリプションキー単位でトークン計測 | `azure-openai-emit-token-metric` → Event Hub → Logic Apps → Cosmos DB |
| **クォータ枯渇** | ユースケース別のトークン上限 | `azure-openai-token-limit` ポリシー |
| **アクセス制御なし** | プロダクト単位の許可モデルリスト | Product + Subscription + Policy |
| **モデル廃止時の改修** | モデルエイリアス | Backend Pool + weighted / priority 戦略 |

### 2.3 モデルエイリアスとルーティング戦略

```mermaid
flowchart LR
    App["アプリ<br/>model='chat-default'"] --> Alias["エイリアス<br/>chat-default"]
    Alias -->|"priority 1"| B1["Foundry Primary<br/>Sweden Central"]
    Alias -->|"priority 2<br/>(フェイルオーバー)"| B2["Foundry Secondary<br/>East US 2"]
    Alias -->|"weight 10%<br/>(カナリア)"| B3["新モデル検証"]
```

| 戦略 | 用途 |
|---|---|
| `priority` | リージョン障害時のフェイルオーバー |
| `weighted` | カナリアリリース、コスト最適化（安価なモデルに一部を流す） |
| `round-robin` | 複数デプロイ間の負荷分散、TPM 上限の合算 |

### 2.4 アクセスコントラクトのデータモデル

```jsonc
[
  {
    "useCase": "sales-customer-support-assistant",
    "businessUnit": "Sales",
    "allowedModels": ["gpt-5-mini", "text-embedding-3-large"],
    "capacityAllocation": {
      "tokensPerMinute": 50000,
      "tokensPerMonth": 20000000
    },
    "storeKeyInKeyVault": true,
    "enableFoundryConnection": true
  },
  {
    "useCase": "finance-report-analyzer",
    "businessUnit": "Finance",
    "allowedModels": ["gpt-5", "gpt-5-mini"],
    "capacityAllocation": { "tokensPerMinute": 200000 }
  }
]
```

これが APIM 上で以下に展開されます。

```mermaid
flowchart LR
    AC["アクセスコントラクト定義<br/>(JSON)"] --> P["APIM Product<br/>ユースケース単位"]
    P --> SK["Subscription Key<br/>チームへ配布"]
    P --> POL["Policy<br/>許可モデル / トークン上限"]
    SK -.オプション.-> KV["Key Vault に保存"]
```

### 2.5 デプロイのモジュール分割 ★重要な設計思想

> 「新しいモデルをオンボードするたびにプラットフォーム全体を再デプロイしなければならないとしたら、
> それは時間がかかり、エラーを起こしやすい作業です。」— Nadeem Shkir

```mermaid
flowchart LR
    M1["**Module 1**<br/>Platform<br/>頻度: 年数回<br/>所要: 25-30 分"]
    M2["**Module 2**<br/>LLM Backend Onboarding<br/>頻度: 週次<br/>所要: 数分"]
    M3["**Module 3**<br/>Access Contracts<br/>頻度: 新チーム参画時<br/>所要: 数分"]
    M1 --> M2 --> M3
    M2 -.再実行.-> M2
    M3 -.再実行.-> M3
```

| モジュール | 変更頻度 | 責任者 | 内容 |
|---|---|---|---|
| Platform | 低（年数回） | プラットフォームチーム | VNet, APIM, PE, Cosmos, Logic Apps, Event Hubs, API Center |
| Backend Onboarding | 中（週次） | プラットフォームチーム | モデルバックエンド追加、エイリアス定義、フェイルオーバー設定 |
| Access Contracts | 中（チーム参画時） | プラットフォームチーム + 各事業部 | プロダクト、キー、ポリシー、クォータ |

---

## 3. 2 つの Landing Zone の統合

```mermaid
flowchart TB
    subgraph Hub["Connectivity Subscription (ALZ platform)"]
        HUBVNET["Hub VNet"]
        FW["Azure Firewall"]
        DNS["Private DNS Zones<br/>集中管理"]
        ER["ExpressRoute / VPN"]
    end

    subgraph GW["AI Hub Prod Subscription"]
        GWVNET["AI Hub VNet (spoke)"]
        APIM["API Management"]
    end

    subgraph AG1["AI Agent Prod Subscription — 事業部 A"]
        VNET1["AI Services VNet (spoke)"]
        F1["Foundry + Agent Service"]
    end

    subgraph AG2["AI Agent Prod Subscription — 事業部 B"]
        VNET2["AI Services VNet (spoke)"]
        F2["Foundry + Agent Service"]
    end

    HUBVNET ---|"VNet Peering"| GWVNET
    HUBVNET ---|"VNet Peering"| VNET1
    HUBVNET ---|"VNet Peering"| VNET2
    DNS -.リンク.-> GWVNET
    DNS -.リンク.-> VNET1
    DNS -.リンク.-> VNET2
    GWVNET -->|"統制されたアクセス"| VNET1
    GWVNET -->|"統制されたアクセス"| VNET2
    APIM --> EXT["外部プロバイダ<br/>Bedrock / Gemini"]
    FW -.全送信を検査.-> GW
    FW -.全送信を検査.-> AG1
    FW -.全送信を検査.-> AG2
```

### デプロイモード

Bicep 実装は `deploymentMode` パラメータで 2 つのモードをサポートします。

| モード | 動作 | 使う場面 |
|---|---|---|
| `standalone` | hub を含むすべてを新規作成 | ALZ 未整備、または独立検証環境 |
| `ailz-integrated` | spoke のみ作成し、既存 hub にピアリング | ALZ 整備済みの本番環境 |

---

## 4. 「本番にスケールしない」アーキテクチャとの差分

冒頭で提示された「よく見るがサインオフできないアーキテクチャ」との差分を整理します。

| 項目 | よくある PoC アーキテクチャ | AI Landing Zone |
|---|---|---|
| ネットワーク | パブリックエンドポイント | VNet + Private Endpoint 15 ゾーン + UDR で送信制御 |
| 認証 | API キー | Managed Identity + Entra RBAC |
| ゲートウェイ | なし（直接呼び出し） | APIM でトークン制限・キャッシュ・ルーティング・監査 |
| コスト帰属 | サブスクリプション一括 | ユースケース別トークン計測 → Cosmos DB |
| モデル管理 | モデル名ハードコード | エイリアス + バックエンドプール |
| 運用アクセス | パブリック IP の VM | Bastion + Jumpbox（パブリック IP なし） |
| CI/CD | ローカル実行 | 閉域内ビルドエージェント + パイプライン |
| 監視 | App Insights 単体 | Diagnostic Settings 全リソース + Log Analytics 集約 + Alerts |
| 安全性 | なし | Content Safety + PII 検出（プラガブル） |
| レジストリ | なし | API Center（Universal AI Registry） |
| DR | 単一リージョン | マルチリージョンバックエンド + priority フェイルオーバー |

---

## 参考

- [設計フレームワーク](03-design-framework.md) — 各設計領域の判断ポイント
- [デプロイガイド](06-deployment-guide.md) — 実際のパラメータ設定
- 公式: https://azure.github.io/AI-Landing-Zones/
