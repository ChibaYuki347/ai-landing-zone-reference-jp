# Azure AI Landing Zones リファレンス（日本語）

> **PoC は動く。しかし本番には出せない。** — この壁を越えるための、Microsoft Foundry を中心とした
> エンタープライズ AI 基盤のリファレンスアーキテクチャと実装です。

このリポジトリは、Microsoft の公式ウェビナー **「Azure AI Landing Zones for Production at Scale」**
（Bilal Amjad / Nadeem Shkir, Microsoft Global AI Cloud Solution Architects）の内容を日本語で書き起こし・
再構成し、**プロフェッショナル開発者・アーキテクトがそのまま本番設計と社内説明に使える形**にまとめたものです。

公式実装（[Azure/bicep-ptn-aiml-landing-zone](https://github.com/Azure/bicep-ptn-aiml-landing-zone) v2.4.1）を
同梱しており、`azd up` で実際に Azure へデプロイできます。

---

## なぜこのリポジトリが必要か

| | AI を本番化できている企業 | できていない企業 |
|---|---|---|
| PoC → 本番までの期間 | **約 12 週間** | **最大 12 か月** |
| ROI 実現 | 12 週間以内に開始 | 未実現のまま |

**2/3 以上の企業が PoC の壁を越えられていません。** 理由はモデルの性能ではなく、
**インフラ・スキル・オペレーティングモデルの不足**です。

AI Landing Zones はこのギャップを、**設計フレームワーク × リファレンスアーキテクチャ × デプロイ可能な実装**
の 3 点セットで埋めます。

```mermaid
flowchart TB
    subgraph L3["3. AI ユースケース (20%)"]
        UC["RAG / 文書処理 / ファインチューニング<br/>エージェント業務自動化"]
    end
    subgraph L2["2. AI Landing Zone (30%)"]
        AILZ["Foundry LZ / AI Gateway LZ<br/>モデル・エージェント・ゲートウェイ・データ"]
    end
    subgraph L1["1. Azure Landing Zone (50%)"]
        ALZ["ネットワーク / ID / ポリシー / 運用監視<br/>プラットフォーム基盤"]
    end
    L1 --> L2 --> L3
```

> **本番 AI アプリの実現に必要な作業の約 80% は、AI ユースケースそのものではなく基盤側にあります。**
> Azure Landing Zone と AI Landing Zone は、この 80% を再利用可能な形で提供します。

---

## ドキュメント構成

| ドキュメント | 内容 | 想定読者 |
|---|---|---|
| **[01. ウェビナー書き起こし](docs/01-webinar-transcript.md)** | 元資料 41 スライド＋動画 44 分の完全書き起こし（日本語） | 全員 |
| **[02. なぜ Microsoft Foundry なのか](docs/02-why-microsoft-foundry.md)** ⭐ | プロ開発者向けの技術的根拠。競合比較、アーキテクチャ的優位性、意思決定基準 | 開発者・アーキテクト |
| **[03. 設計フレームワーク](docs/03-design-framework.md)** | 12 の設計領域 × WAF 5 本柱。設計チェックリスト | アーキテクト |
| **[04. リファレンスアーキテクチャ](docs/04-reference-architecture.md)** | Foundry LZ / AI Gateway LZ の詳細構成図と設計判断 | アーキテクト・インフラ |
| **[05. トークトラック](docs/05-talk-track.md)** ⭐ | 顧客・社内説明用の話法スクリプト（5分 / 15分 / 45分版） | プリセールス・CSA |
| **[06. デプロイガイド](docs/06-deployment-guide.md)** | `azd up` による実デプロイ手順、パラメータ設計、コスト見積 | インフラ・DevOps |
| **[07. 用語と命名の変遷](docs/07-naming-and-terminology.md)** | Azure AI Foundry → Microsoft Foundry など 2026 年時点の正式名称 | 全員 |

---

## クイックスタート

```powershell
# 1. 前提ツール
winget install Microsoft.AzureCLI
winget install Microsoft.Azd

# 2. ログイン
az login
azd auth login

# 3. プリセットを適用（minimal / secure / full）
.\scripts\Set-Preset.ps1 -Preset minimal -EnvName ailz-demo

# 4. デプロイ
cd infra-upstream
azd up

# 5. 確認
cd ..
.\scripts\Test-Deployment.ps1

# 6. 削除（重要）
cd infra-upstream
azd down --force --purge
```

### プリセット早見表

| プリセット | 所要時間 | 概算コスト（月/インフラのみ） | 用途 |
|---|---|---|---|
| **`minimal`** | 10-15 分 | ~US$400 | 機能確認、開発、デモ |
| **`secure`** | 20-25 分 | ~US$785 | 本番相当の検証（閉域、Firewall なし） |
| **`full`** | 30-40 分 | ~US$1,715 | 規制業種の本番相当（Firewall あり） |

詳細は **[デプロイガイド](docs/06-deployment-guide.md)** を参照してください。

> [!WARNING]
> 上記はインフラのみの概算で、**モデルのトークン利用料は別途発生します。**
> `full` は Azure Firewall（月 ~US$900）が最大のコスト要因です。
> **検証後は必ず `azd down --force --purge` で削除してください。**
> `--purge` を付けないと Key Vault / App Configuration が論理削除状態で残り、
> 同じ名前で再デプロイできなくなります。

---

## リポジトリ構成

```
ai-landing-zone-reference-jp/
├── README.md                      # このファイル
├── LICENSE                        # MIT
├── docs/                          # 日本語ドキュメント
│   ├── 01-webinar-transcript.md   # 元資料の完全書き起こし
│   ├── 02-why-microsoft-foundry.md ⭐
│   ├── 03-design-framework.md     # 12 設計領域 × WAF
│   ├── 04-reference-architecture.md
│   ├── 05-talk-track.md           ⭐ 5分/15分/45分の話法
│   ├── 06-deployment-guide.md     # azd 手順・環境変数・コスト
│   ├── 07-naming-and-terminology.md
│   └── images/                    # アーキテクチャ図
├── presets/                       # 環境別パラメータプリセット
│   ├── minimal.env                #   デモ・開発（~US$400/月）
│   ├── secure.env                 #   閉域（~US$785/月）
│   └── full.env                   #   Firewall 込み（~US$1,715/月）
├── scripts/
│   ├── Set-Preset.ps1             # プリセットを azd 環境に適用
│   └── Test-Deployment.ps1        # デプロイ結果の検証
└── infra-upstream/                # 公式 Bicep 実装 v2.4.1 同梱
    ├── main.bicep
    ├── main.parameters.json       #   158 パラメータ
    ├── azure.yaml
    ├── modules/
    ├── scripts/
    └── docs/                      #   上流ランブック（英語）
```

---

## こんなときに読む

| 状況 | 読むもの |
|---|---|
| まず全体像を知りたい | [01. ウェビナー書き起こし](docs/01-webinar-transcript.md) |
| 開発チームに Foundry を説明したい | [02. なぜ Microsoft Foundry なのか](docs/02-why-microsoft-foundry.md) |
| 自分のプロジェクトの抜け漏れを確認したい | [03. 設計フレームワーク](docs/03-design-framework.md) のチェックリスト |
| 構成図が欲しい | [04. リファレンスアーキテクチャ](docs/04-reference-architecture.md) |
| 明日プレゼンがある | [05. トークトラック](docs/05-talk-track.md) |
| とにかく動かしたい | [06. デプロイガイド](docs/06-deployment-guide.md#最小構成での検証) |
| 古い記事の用語がわからない | [07. 用語と命名](docs/07-naming-and-terminology.md) |

---

## 参照リンク

| リソース | URL |
|---|---|
| AI Landing Zones 公式ドキュメント | https://aka.ms/AILZ |
| Bicep 実装 | https://github.com/Azure/bicep-ptn-aiml-landing-zone |
| Terraform 実装 | https://github.com/Azure/terraform-azurerm-avm-ptn-aiml-landing-zone |
| AI Hub Gateway (APIM) 実装 | https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator |
| Cloud Adoption Framework - AI | https://learn.microsoft.com/azure/cloud-adoption-framework/scenarios/ai/ |
| Well-Architected Framework - AI Workload | https://learn.microsoft.com/azure/well-architected/ai/ |
| Microsoft Foundry ドキュメント | https://learn.microsoft.com/azure/ai-foundry/ |

---

## ライセンス

本リポジトリのドキュメントは MIT ライセンスです。`infra-upstream/` 配下は
[Azure/bicep-ptn-aiml-landing-zone](https://github.com/Azure/bicep-ptn-aiml-landing-zone) の MIT ライセンスに従います。

元資料の著作権は Microsoft Corporation に帰属します。本リポジトリは技術理解を目的とした
日本語での再構成であり、Microsoft の公式ドキュメントではありません。
