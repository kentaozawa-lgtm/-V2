-- 領収書読み取りアプリ データベーススキーマ
-- Supabase用SQL

-- 組織（会社）テーブル
CREATE TABLE organizations (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ユーザープロファイルテーブル
CREATE TABLE profiles (
  id UUID REFERENCES auth.users(id) PRIMARY KEY,
  email TEXT NOT NULL,
  display_name TEXT NOT NULL,
  organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('member', 'admin')),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 勘定科目マスタ
CREATE TABLE account_titles (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(organization_id, name)
);

-- 税区分マスタ
CREATE TABLE tax_categories (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  rate NUMERIC(4, 2),
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(organization_id, name)
);

-- 支払方法マスタ
CREATE TABLE payment_methods (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  account_name TEXT, -- freee側の決済口座名
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(organization_id, name)
);

-- 領収書テーブル
CREATE TABLE receipts (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
  created_by UUID REFERENCES profiles(id),
  
  -- 画像
  image_url TEXT NOT NULL,
  
  -- 抽出データ
  receipt_date DATE NOT NULL,
  vendor TEXT,
  amount NUMERIC(12, 2) NOT NULL,
  
  -- 分類
  account_title_id UUID REFERENCES account_titles(id),
  tax_category_id UUID REFERENCES tax_categories(id),
  payment_method_id UUID REFERENCES payment_methods(id),
  
  -- インボイス
  invoice_number TEXT,
  tax_rate NUMERIC(4, 2),
  
  -- メモ
  memo TEXT,
  
  -- ステータス: draft, rejected, approved, exported
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'rejected', 'approved', 'exported')),
  
  -- 差し戻し情報
  rejection_comment TEXT,
  rejection_fields TEXT[], -- 修正が必要なフィールド名の配列
  
  -- 承認情報
  approved_by UUID REFERENCES profiles(id),
  approved_at TIMESTAMPTZ,
  
  -- Gemini生データ（JSON）
  ai_raw_data JSONB,
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- CSV出力履歴テーブル
CREATE TABLE export_history (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
  export_month TEXT NOT NULL, -- YYYY-MM形式
  exported_by UUID REFERENCES profiles(id),
  exported_at TIMESTAMPTZ DEFAULT NOW(),
  receipt_count INTEGER NOT NULL,
  file_url TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS (Row Level Security) ポリシー

-- organizations: 自分の組織のみ
ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their organization"
  ON organizations FOR SELECT
  USING (
    id IN (
      SELECT organization_id FROM profiles WHERE id = auth.uid()
    )
  );

-- profiles: 自分のプロファイルと同じ組織のプロファイルを閲覧可能
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own profile"
  ON profiles FOR SELECT
  USING (id = auth.uid());

CREATE POLICY "Users can view profiles in their organization"
  ON profiles FOR SELECT
  USING (
    organization_id IN (
      SELECT organization_id FROM profiles WHERE id = auth.uid()
    )
  );

CREATE POLICY "Users can update their own profile"
  ON profiles FOR UPDATE
  USING (id = auth.uid());

-- マスタテーブル: 同じ組織のデータのみ、adminは編集可能
ALTER TABLE account_titles ENABLE ROW LEVEL SECURITY;
ALTER TABLE tax_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_methods ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view masters in their organization"
  ON account_titles FOR SELECT
  USING (
    organization_id IN (
      SELECT organization_id FROM profiles WHERE id = auth.uid()
    )
  );

CREATE POLICY "Admins can manage account titles"
  ON account_titles FOR ALL
  USING (
    organization_id IN (
      SELECT organization_id FROM profiles WHERE id = auth.uid() AND role = 'admin'
    )
  );

CREATE POLICY "Users can view tax categories in their organization"
  ON tax_categories FOR SELECT
  USING (
    organization_id IN (
      SELECT organization_id FROM profiles WHERE id = auth.uid()
    )
  );

CREATE POLICY "Admins can manage tax categories"
  ON tax_categories FOR ALL
  USING (
    organization_id IN (
      SELECT organization_id FROM profiles WHERE id = auth.uid() AND role = 'admin'
    )
  );

CREATE POLICY "Users can view payment methods in their organization"
  ON payment_methods FOR SELECT
  USING (
    organization_id IN (
      SELECT organization_id FROM profiles WHERE id = auth.uid()
    )
  );

CREATE POLICY "Admins can manage payment methods"
  ON payment_methods FOR ALL
  USING (
    organization_id IN (
      SELECT organization_id FROM profiles WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- receipts: 社員は自分のもののみ、経理は全件
ALTER TABLE receipts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members can view their own receipts"
  ON receipts FOR SELECT
  USING (
    created_by = auth.uid()
    OR
    EXISTS (
      SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'
    )
  );

CREATE POLICY "Users can create receipts"
  ON receipts FOR INSERT
  WITH CHECK (
    created_by = auth.uid()
    AND
    organization_id IN (
      SELECT organization_id FROM profiles WHERE id = auth.uid()
    )
  );

CREATE POLICY "Members can update their own drafts"
  ON receipts FOR UPDATE
  USING (
    created_by = auth.uid() AND status = 'draft'
  );

CREATE POLICY "Admins can update any receipt"
  ON receipts FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- export_history: 経理のみ
ALTER TABLE export_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can view export history"
  ON export_history FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'
    )
  );

CREATE POLICY "Admins can create export history"
  ON export_history FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- インデックス
CREATE INDEX idx_receipts_organization ON receipts(organization_id);
CREATE INDEX idx_receipts_created_by ON receipts(created_by);
CREATE INDEX idx_receipts_status ON receipts(status);
CREATE INDEX idx_receipts_date ON receipts(receipt_date);
CREATE INDEX idx_export_history_organization ON export_history(organization_id);
CREATE INDEX idx_export_history_month ON export_history(export_month);

-- 初期データ（サンプル組織・マスタ）
INSERT INTO organizations (id, name) VALUES 
  ('00000000-0000-0000-0000-000000000001', 'サンプル株式会社');

-- 勘定科目の初期データ
INSERT INTO account_titles (organization_id, name) VALUES
  ('00000000-0000-0000-0000-000000000001', '消耗品費'),
  ('00000000-0000-0000-0000-000000000001', '旅費交通費'),
  ('00000000-0000-0000-0000-000000000001', '会議費'),
  ('00000000-0000-0000-0000-000000000001', '通信費'),
  ('00000000-0000-0000-0000-000000000001', '図書費'),
  ('00000000-0000-0000-0000-000000000001', '接待交際費');

-- 税区分の初期データ
INSERT INTO tax_categories (organization_id, name, rate) VALUES
  ('00000000-0000-0000-0000-000000000001', '課税10%', 10.00),
  ('00000000-0000-0000-0000-000000000001', '軽減8%', 8.00),
  ('00000000-0000-0000-0000-000000000001', '非課税', 0.00),
  ('00000000-0000-0000-0000-000000000001', '不課税', 0.00);

-- 支払方法の初期データ
INSERT INTO payment_methods (organization_id, name, account_name) VALUES
  ('00000000-0000-0000-0000-000000000001', '現金', '現金'),
  ('00000000-0000-0000-0000-000000000001', 'クレジットカード', '法人カード'),
  ('00000000-0000-0000-0000-000000000001', '交通系IC', 'Suica'),
  ('00000000-0000-0000-0000-000000000001', 'プリペイドカード', 'プリペイド');

-- トリガー: updated_at自動更新
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_organizations_updated_at BEFORE UPDATE ON organizations
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_profiles_updated_at BEFORE UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_account_titles_updated_at BEFORE UPDATE ON account_titles
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_tax_categories_updated_at BEFORE UPDATE ON tax_categories
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_payment_methods_updated_at BEFORE UPDATE ON payment_methods
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_receipts_updated_at BEFORE UPDATE ON receipts
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
