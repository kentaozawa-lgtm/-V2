# 領収書読み取りアプリ

領収書を撮影してAIで自動解析し、経理承認を経てfreee会計用CSVを出力するWebアプリケーション。

## 技術スタック

- **フレームワーク**: Next.js 15 (App Router)
- **UI**: shadcn/ui + Tailwind CSS + Framer Motion
- **データベース**: Supabase (PostgreSQL)
- **認証**: Supabase Auth
- **ストレージ**: Supabase Storage
- **AI解析**: Google Gemini (gemini-1.5-flash)
- **言語**: TypeScript

## 主な機能

### 社員向け機能
- 📸 領収書の撮影・アップロード
- 🤖 AIによる自動項目抽出
- ✏️ 解析結果の確認・修正
- 📋 自分の領収書一覧
- 🔄 差し戻し対応

### 経理向け機能
- 👁️ 全領収書の閲覧・管理
- ✅ 内容確認・承認
- 🔙 差し戻し（コメント付き）
- 📊 月次CSV出力（freee会計用）
- ⚙️ マスタ管理（勘定科目/税区分/支払方法）

## セットアップ

### 1. 前提条件

- Node.js 18以上
- Supabaseアカウント
- Google Cloud Platform（Gemini API）アカウント

### 2. Supabaseプロジェクト作成

1. [Supabase](https://supabase.com)でプロジェクトを作成
2. `DATABASE_SCHEMA.sql`を実行してテーブル作成
3. Storage バケット `receipts` を作成（Public設定）

### 3. 環境変数設定

`.env.local.example` をコピーして `.env.local` を作成:

```bash
cp .env.local.example .env.local
```

以下の環境変数を設定:

```env
# Supabase
NEXT_PUBLIC_SUPABASE_URL=your-project-url.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=your-anon-key
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key

# Google Gemini
GEMINI_API_KEY=your-gemini-api-key

# App
NEXT_PUBLIC_APP_URL=http://localhost:3000
```

### 4. 依存関係のインストール

```bash
npm install
```

### 5. 開発サーバー起動

```bash
npm run dev
```

http://localhost:3000 でアクセス可能

## データベーススキーマ

### 主要テーブル

- `organizations` - 組織（会社）
- `profiles` - ユーザープロファイル
- `receipts` - 領収書データ
- `account_titles` - 勘定科目マスタ
- `tax_categories` - 税区分マスタ
- `payment_methods` - 支払方法マスタ
- `export_history` - CSV出力履歴

詳細は `DATABASE_SCHEMA.sql` を参照

## ユーザー登録

初回のユーザー登録は、Supabaseダッシュボードから手動で行います:

1. Authentication → Users → Add user
2. `profiles` テーブルにレコード追加:
   ```sql
   INSERT INTO profiles (id, email, display_name, organization_id, role)
   VALUES (
     'user-uuid-from-auth',
     'user@example.com',
     '山田太郎',
     '00000000-0000-0000-0000-000000000001',
     'admin'  -- または 'member'
   );
   ```

## 画面構成

### 認証
- `/login` - ログイン画面

### アプリケーション（要認証）
- `/scan` - 領収書撮影（初期画面）
- `/scan/review` - 解析結果確認・編集
- `/receipts` - 領収書一覧
- `/receipts/[id]` - 領収書詳細
- `/receipts/[id]/edit` - 領収書編集（経理のみ）
- `/admin/masters` - マスタ管理（経理のみ）
- `/admin/exports` - CSV出力履歴（経理のみ）
- `/account` - アカウント情報

## ワークフロー

1. **社員**: 領収書を撮影 → AI解析 → 内容確認 → 下書き保存
2. **経理**: 一覧で確認 → 修正必要なら差し戻し / 問題なければ承認
3. **社員**: 差し戻しがあれば修正して再提出
4. **経理**: 月次で承認済みをCSV出力 → freee会計にインポート

## CSV出力仕様

### 出力項目

- 発生日
- 収支区分（固定: "支出"）
- 勘定科目
- 金額
- 税区分
- 決済口座
- 取引先
- 備考（インボイス番号/税率/メモ）

### freee会計への取り込み

1. freee会計にログイン
2. 取引 → 取引の一括登録
3. CSVファイルをアップロード
4. 列マッピングを確認
5. インポート実行

## 開発時の注意点

### AI解析

- Gemini API は無料枠あり（月50リクエストまで）
- 画像は1600px以下に圧縮して送信
- 解析結果は候補として扱い、人間が最終確定

### スマホ対応

- カメラ起動は HTTPS 必須（本番環境）
- iOS Safari 対応のため `font-size: 16px` 設定済み
- 下部ナビゲーションは固定（親指届く範囲）

### RLS（Row Level Security）

- Supabaseで有効化済み
- 社員は自分のデータのみ閲覧可能
- 経理（admin）は全データ閲覧・編集可能

## トラブルシューティング

### カメラが起動しない

- HTTPS 接続を確認
- ブラウザのカメラ権限を確認
- モバイルの場合、アプリ設定も確認

### AI解析が失敗する

- Gemini API キーを確認
- 画像サイズ・形式を確認（JPEG/PNG推奨）
- API制限（無料枠）を確認

### データが表示されない

- Supabase の RLS ポリシーを確認
- ユーザーの `organization_id` が正しいか確認
- ブラウザのコンソールでエラー確認

## ライセンス

このプロジェクトはサンプル実装です。商用利用の際は各ライブラリのライセンスを確認してください。

## 今後の拡張案

- [ ] freee API 直接連携
- [ ] 経費精算ワークフロー（上長承認）
- [ ] 交通費IC履歴連携
- [ ] クレカ明細自動取り込み
- [ ] スマホアプリ化（PWA/React Native）
- [ ] OCR精度向上（複数AI比較）
- [ ] 領収書検索機能
- [ ] ダッシュボード・分析機能
