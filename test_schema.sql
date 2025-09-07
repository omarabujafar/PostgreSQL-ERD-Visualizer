-- ============================================================
-- ENUM TYPES (from your doc's allowed values)
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'kyc_status_enum') THEN
    CREATE TYPE kyc_status_enum AS ENUM ('PENDING','APPROVED','FAILED','REVIEW');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'connection_status_enum') THEN
    CREATE TYPE connection_status_enum AS ENUM ('ACTIVE','EXPIRED','REVOKED','ERROR');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'direction_enum') THEN
    CREATE TYPE direction_enum AS ENUM ('INCOMING','OUTGOING');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'group_type_enum') THEN
    CREATE TYPE group_type_enum AS ENUM ('AD_HOC_SPLIT','RECURRING');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'group_role_enum') THEN
    CREATE TYPE group_role_enum AS ENUM ('ADMIN','MEMBER');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'payring_role_enum') THEN
    CREATE TYPE payring_role_enum AS ENUM ('PAYER','PARTICIPANT');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'parent_container_type_enum') THEN
    CREATE TYPE parent_container_type_enum AS ENUM ('GROUP','PAY_RING');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'split_method_enum') THEN
    CREATE TYPE split_method_enum AS ENUM ('EQUAL','PERCENT','AMOUNT','ITEMISED');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'obligation_status_enum') THEN
    CREATE TYPE obligation_status_enum AS ENUM ('PENDING','SETTLED','CANCELLED');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'settlement_status_enum') THEN
    CREATE TYPE settlement_status_enum AS ENUM ('PENDING','COMPLETED','FAILED','CANCELLED','REFUNDED');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'interval_enum') THEN
    CREATE TYPE interval_enum AS ENUM ('DAILY','WEEKLY','MONTHLY','YEARLY');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'reminder_scope_enum') THEN
    CREATE TYPE reminder_scope_enum AS ENUM ('OBLIGATION','SETTLEMENT_ATTEMPT');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'strategy_enum') THEN
    CREATE TYPE strategy_enum AS ENUM ('DEFAULT','CUSTOM');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'channel_enum') THEN
    CREATE TYPE channel_enum AS ENUM ('PUSH','EMAIL','INAPP');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'token_status_enum') THEN
    CREATE TYPE token_status_enum AS ENUM ('ACTIVE','EXPIRED','REVOKED');
  END IF;
END $$;

-- ============================================================
-- TABLES FROM YOUR PDF
-- ============================================================

-- USER
CREATE TABLE IF NOT EXISTS "USER" (
  "UserID" UUID PRIMARY KEY,
  "Email" TEXT UNIQUE,
  "Phone" TEXT NOT NULL UNIQUE,
  "Username" TEXT NOT NULL UNIQUE,
  "DisplayName" TEXT NOT NULL,
  "Bio" TEXT,
  "Avatar" TEXT,
  "KYC" kyc_status_enum NOT NULL DEFAULT 'PENDING',
  "CanReceivePayments" BOOLEAN NOT NULL DEFAULT FALSE,
  "TOSVersion" TEXT,
  "MarketingOptIn" BOOLEAN NOT NULL DEFAULT FALSE,
  "DateCreated" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "DateUpdated" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "DateDeleted" TIMESTAMPTZ
);

-- USERNAMECHANGE
CREATE TABLE IF NOT EXISTS "USERNAMECHANGE" (
  "UsernameID" UUID PRIMARY KEY,
  "UserID" UUID NOT NULL REFERENCES "USER"("UserID") ON DELETE CASCADE,
  "OldUsername" TEXT NOT NULL,
  "NewUsername" TEXT NOT NULL,
  "DateChanged" TIMESTAMPTZ NOT NULL
);
-- Enforce cooldown in app logic by checking most recent change.

-- KYCVERIFICATION
CREATE TABLE IF NOT EXISTS "KYCVERIFICATION" (
  "KYCID" UUID PRIMARY KEY,
  "UserID" UUID NOT NULL REFERENCES "USER"("UserID") ON DELETE CASCADE,
  "Provider" TEXT NOT NULL,
  "ReferenceID" TEXT NOT NULL,
  "Status" kyc_status_enum NOT NULL DEFAULT 'PENDING',
  "SubmittedAt" TIMESTAMPTZ,
  "DecidedAt" TIMESTAMPTZ,
  "FailureReason" TEXT,
  "ResultPayload" JSONB,
  "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "UpdatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- AISCONNECTION
CREATE TABLE IF NOT EXISTS "AISCONNECTION" (
  "AISID" UUID PRIMARY KEY,
  "UserID" UUID NOT NULL REFERENCES "USER"("UserID") ON DELETE CASCADE,
  "Provider" TEXT NOT NULL,
  "ConnectionRef" TEXT NOT NULL,
  "Status" connection_status_enum NOT NULL DEFAULT 'ACTIVE',
  "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "UpdatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- BANKACCOUNT
CREATE TABLE IF NOT EXISTS "BANKACCOUNT" (
  "BankAccountID" UUID PRIMARY KEY,
  "UserID" UUID NOT NULL REFERENCES "USER"("UserID") ON DELETE CASCADE,
  "Provider" TEXT NOT NULL,
  "ProviderAccountID" TEXT NOT NULL,
  "InstitutionID" TEXT,
  "DisplayLabel" TEXT,
  "LastFourDigits" TEXT,
  "Currency" CHAR(3) NOT NULL,
  "Status" connection_status_enum NOT NULL DEFAULT 'ACTIVE',
  "Active" BOOLEAN NOT NULL DEFAULT TRUE,
  "ProviderConnectionID" UUID REFERENCES "PROVIDERCONNECTION"("ProviderConnectionID"),
  "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "UpdatedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE ("Provider","ProviderAccountID")
);

-- PROVIDERCONNECTION
CREATE TABLE IF NOT EXISTS "PROVIDERCONNECTION" (
  "ProviderConnectionID" UUID PRIMARY KEY,
  "UserID" UUID NOT NULL REFERENCES "USER"("UserID") ON DELETE CASCADE,
  "Provider" TEXT NOT NULL,
  "ConnectionRef" TEXT,
  "Status" connection_status_enum NOT NULL DEFAULT 'ACTIVE',
  "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "UpdatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- CONSENTGRANT
CREATE TABLE IF NOT EXISTS "CONSENTGRANT" (
  "ConsentGrantID" UUID PRIMARY KEY,
  "UserID" UUID NOT NULL REFERENCES "USER"("UserID") ON DELETE CASCADE,
  "Provider" TEXT NOT NULL,
  "ConsentRef" TEXT[] NOT NULL,
  "Scope" TEXT[] NOT NULL,
  "GrantedAt" TIMESTAMPTZ NOT NULL,
  "ExpiresAt" TIMESTAMPTZ,
  "RevokedAt" TIMESTAMPTZ,
  "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- BANKACCOUNTCONSENT
CREATE TABLE IF NOT EXISTS "BANKACCOUNTCONSENT" (
  "BankConsentID" UUID PRIMARY KEY,
  "BankAccountID" UUID NOT NULL REFERENCES "BANKACCOUNT"("BankAccountID") ON DELETE CASCADE,
  "ConsentID" UUID NOT NULL REFERENCES "CONSENTGRANT"("ConsentGrantID") ON DELETE CASCADE,
  "IsCurrent" BOOLEAN NOT NULL
);

-- BANKACCOUNTPRIORITY
CREATE TABLE IF NOT EXISTS "BANKACCOUNTPRIORITY" (
  "BankPriorityID" UUID PRIMARY KEY,
  "BankAccountID" UUID NOT NULL REFERENCES "BANKACCOUNT"("BankAccountID") ON DELETE CASCADE,
  "Direction" direction_enum NOT NULL,
  "Rank" INT NOT NULL,
  "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE ("BankAccountID","Direction","Rank")
);

-- Helpful indexes for the PDF tables
CREATE INDEX IF NOT EXISTS user_phone_idx ON "USER" ("Phone");
CREATE INDEX IF NOT EXISTS user_username_idx ON "USER" ("Username");
CREATE INDEX IF NOT EXISTS kycv_user_idx ON "KYCVERIFICATION" ("UserID","Status");
CREATE INDEX IF NOT EXISTS ba_user_idx ON "BANKACCOUNT" ("UserID","Active");

-- ============================================================
-- ADDITIONAL TABLES (the rest of your spec)
-- ============================================================

-- AUDITLOG
CREATE TABLE IF NOT EXISTS "AuditLog" (
  "AuditID" BIGSERIAL PRIMARY KEY,
  "ActorUserID" UUID REFERENCES "USER"("UserID") ON DELETE SET NULL,
  "Action" TEXT NOT NULL,
  "EntityType" TEXT NOT NULL,
  "EntityID" TEXT NOT NULL,
  "Metadata" JSONB DEFAULT '{}'::jsonb,
  "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS auditlog_entity_idx ON "AuditLog" ("EntityType","EntityID");
CREATE INDEX IF NOT EXISTS auditlog_created_idx ON "AuditLog" ("CreatedAt");

-- DATAERASUREREQUEST
CREATE TABLE IF NOT EXISTS "DataErasureRequest" (
  "ErasureRequestID" UUID PRIMARY KEY,
  "UserID" UUID NOT NULL REFERENCES "USER"("UserID") ON DELETE CASCADE,
  "RequestedAt" TIMESTAMPTZ NOT NULL,
  "CompletedAt" TIMESTAMPTZ,
  "Scope" TEXT NOT NULL
);

-- AISACCESSTOKEN (short-lived tokens; one ACTIVE per AISID)
CREATE TABLE IF NOT EXISTS "AISAccessToken" (
  "AISTokenID" UUID PRIMARY KEY,
  "AISID" UUID NOT NULL REFERENCES "AISCONNECTION"("AISID") ON DELETE CASCADE,
  "TokenHash" TEXT NOT NULL,
  "Scopes" TEXT[] NOT NULL,
  "ExpiresAt" TIMESTAMPTZ NOT NULL,
  "RotatedAt" TIMESTAMPTZ,
  "Status" token_status_enum NOT NULL DEFAULT 'ACTIVE',
  "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE ("AISID") WHERE ("Status" = 'ACTIVE')
);
CREATE INDEX IF NOT EXISTS aistoken_expires_idx ON "AISAccessToken" ("ExpiresAt");

-- PROVIDERACCOUNT (counterparty linkage if needed)
CREATE TABLE IF NOT EXISTS "ProviderAccount" (
  "ProviderAccountID" BIGSERIAL PRIMARY KEY,
  "UserID" UUID NOT NULL REFERENCES "USER"("UserID") ON DELETE CASCADE,
  "Provider" TEXT NOT NULL,
  "ExternalID" TEXT NOT NULL,
  "Status" TEXT NOT NULL,
  "Capabilities" TEXT[] NOT NULL DEFAULT '{}',
  "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "UpdatedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE ("Provider","ExternalID")
);

-- PAYMENTWEBHOOKEVENT + IDEMPOTENCYKEY
CREATE TABLE IF NOT EXISTS "PaymentWebhookEvent" (
  "Provider" TEXT NOT NULL,
  "ProviderEventID" TEXT NOT NULL,
  "Type" TEXT NOT NULL,
  "RawPayload" JSONB NOT NULL,
  "ReceivedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "Processed" BOOLEAN NOT NULL DEFAULT FALSE,
  "ProcessedAt" TIMESTAMPTZ,
  "Signature" TEXT,
  "DeliveryAttempts" INT NOT NULL DEFAULT 0 CHECK ("DeliveryAttempts" >= 0),
  PRIMARY KEY ("Provider","ProviderEventID")
);
CREATE INDEX IF NOT EXISTS pwe_processed_idx ON "PaymentWebhookEvent" ("Processed");

CREATE TABLE IF NOT EXISTS "IdempotencyKey" (
  "Scope" TEXT NOT NULL,
  "Key" TEXT NOT NULL,
  "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY ("Scope","Key")
);

-- GROUPS / MEMBERS / PAY RINGS
CREATE TABLE IF NOT EXISTS "Group" (
  "GroupID" BIGSERIAL PRIMARY KEY,
  "Name" TEXT NOT NULL,
  "Type" group_type_enum NOT NULL,
  "CreatedBy" UUID NOT NULL REFERENCES "USER"("UserID") ON DELETE RESTRICT,
  "Settings" JSONB NOT NULL DEFAULT '{}'::jsonb,
  "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "UpdatedAt" TIMESTAMPTZ,
  "DeletedAt" TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS "GroupMember" (
  "GroupMemberID" BIGSERIAL PRIMARY KEY,
  "GroupID" BIGINT NOT NULL REFERENCES "Group"("GroupID") ON DELETE CASCADE,
  "UserID" UUID NOT NULL REFERENCES "USER"("UserID") ON DELETE CASCADE,
  "Role" group_role_enum NOT NULL,
  "JoinedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "DeletedAt" TIMESTAMPTZ,
  UNIQUE ("GroupID","UserID")
);

CREATE TABLE IF NOT EXISTS "PayRing" (
  "PayRingID" BIGSERIAL PRIMARY KEY,
  "CreatedBy" UUID NOT NULL REFERENCES "USER"("UserID") ON DELETE RESTRICT,
  "Context" JSONB NOT NULL DEFAULT '{}'::jsonb,
  "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "ExpiresAt" TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS "PayRingMember" (
  "PayRingMemberID" BIGSERIAL PRIMARY KEY,
  "PayRingID" BIGINT NOT NULL REFERENCES "PayRing"("PayRingID") ON DELETE CASCADE,
  "UserID" UUID NOT NULL REFERENCES "USER"("UserID") ON DELETE CASCADE,
  "Role" payring_role_enum NOT NULL,
  UNIQUE ("PayRingID","UserID")
);

-- EXPENSES / ITEMS / SPLITS / OBLIGATIONS
CREATE TABLE IF NOT EXISTS "Expense" (
  "ExpenseID" BIGSERIAL PRIMARY KEY,
  "ParentContainerType" parent_container_type_enum NOT NULL,
  "ParentContainerID" BIGINT NOT NULL,
  "CreatedBy" UUID NOT NULL REFERENCES "USER"("UserID") ON DELETE RESTRICT,
  "Description" TEXT NOT NULL,
  "Currency" CHAR(3) NOT NULL,
  "TotalAmountMinor" BIGINT NOT NULL CHECK ("TotalAmountMinor" >= 0),
  "OccurredAt" TIMESTAMPTZ NOT NULL,
  "DeletedAt" TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS expense_parent_idx
  ON "Expense" ("ParentContainerType","ParentContainerID","OccurredAt");

CREATE TABLE IF NOT EXISTS "ExpenseItem" (
  "ExpenseItemID" BIGSERIAL PRIMARY KEY,
  "ExpenseID" BIGINT NOT NULL REFERENCES "Expense"("ExpenseID") ON DELETE CASCADE,
  "Label" TEXT NOT NULL,
  "AmountMinor" BIGINT NOT NULL CHECK ("AmountMinor" >= 0),
  "DefaultAssignedUserID" UUID REFERENCES "USER"("UserID") ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS "SplitRule" (
  "SplitRuleID" BIGSERIAL PRIMARY KEY,
  "ExpenseID" BIGINT NOT NULL UNIQUE REFERENCES "Expense"("ExpenseID") ON DELETE CASCADE,
  "Method" split_method_enum NOT NULL,
  "RulePayload" JSONB NOT NULL DEFAULT '{}'::jsonb,
  "ComputedAt" TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS "Obligation" (
  "ObligationID" BIGSERIAL PRIMARY KEY,
  "ExpenseID" BIGINT NOT NULL REFERENCES "Expense"("ExpenseID") ON DELETE CASCADE,
  "DebtorUserID" UUID NOT NULL REFERENCES "USER"("UserID") ON DELETE RESTRICT,
  "CreditorUserID" UUID NOT NULL REFERENCES "USER"("UserID") ON DELETE RESTRICT,
  "AmountMinor" BIGINT NOT NULL CHECK ("AmountMinor" >= 0),
  "Status" obligation_status_enum NOT NULL DEFAULT 'PENDING',
  "SettledAt" TIMESTAMPTZ,
  UNIQUE ("ExpenseID","DebtorUserID")
);
CREATE INDEX IF NOT EXISTS obligation_inbox_idx ON "Obligation" ("DebtorUserID","Status");

-- SETTLEMENTS / REFUNDS
CREATE TABLE IF NOT EXISTS "SettlementAttempt" (
  "SettlementAttemptID" BIGSERIAL PRIMARY KEY,
  "ObligationID" BIGINT NOT NULL REFERENCES "Obligation"("ObligationID") ON DELETE CASCADE,
  "DebtorUserID" UUID NOT NULL REFERENCES "USER"("UserID") ON DELETE RESTRICT,
  "CreditorUserID" UUID NOT NULL REFERENCES "USER"("UserID") ON DELETE RESTRICT,
  "InitiatedByUserID" UUID NOT NULL REFERENCES "USER"("UserID") ON DELETE RESTRICT,
  "Provider" TEXT NOT NULL,
  "ProviderPaymentID" TEXT,
  "AmountMinor" BIGINT NOT NULL CHECK ("AmountMinor" >= 0),
  "Currency" CHAR(3) NOT NULL,
  "Status" settlement_status_enum NOT NULL DEFAULT 'PENDING',
  "ErrorCode" TEXT,
  "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "CompletedAt" TIMESTAMPTZ,
  "FailedAt" TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS settlement_lookup_idx ON "SettlementAttempt" ("ObligationID","Status","CreatedAt");

CREATE TABLE IF NOT EXISTS "Refund" (
  "RefundID" BIGSERIAL PRIMARY KEY,
  "SettlementAttemptID" BIGINT NOT NULL REFERENCES "SettlementAttempt"("SettlementAttemptID") ON DELETE CASCADE,
  "ProviderRefundID" TEXT,
  "AmountMinor" BIGINT NOT NULL CHECK ("AmountMinor" >= 0),
  "Status" TEXT NOT NULL,
  "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "CompletedAt" TIMESTAMPTZ,
  "FailedAt" TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS refund_settlement_idx ON "Refund" ("SettlementAttemptID");

-- RECURRING SCHEDULES
CREATE TABLE IF NOT EXISTS "RecurringSchedule" (
  "RecurringScheduleID" BIGSERIAL PRIMARY KEY,
  "GroupID" BIGINT NOT NULL REFERENCES "Group"("GroupID") ON DELETE CASCADE,
  "CreatedBy" UUID NOT NULL REFERENCES "USER"("UserID") ON DELETE RESTRICT,
  "Description" TEXT NOT NULL,
  "AmountMinor" BIGINT NOT NULL CHECK ("AmountMinor" >= 0),
  "Currency" CHAR(3) NOT NULL,
  "Method" TEXT NOT NULL CHECK ("Method" IN ('EQUAL','PERCENT')),
  "Percentages" JSONB,
  "Interval" interval_enum NOT NULL,
  "Timezone" TEXT NOT NULL,
  "NextRunAt" TIMESTAMPTZ NOT NULL,
  "LastRunAt" TIMESTAMPTZ,
  "IsActive" BOOLEAN NOT NULL DEFAULT TRUE
);
CREATE INDEX IF NOT EXISTS recurringschedule_next_idx ON "RecurringSchedule" ("NextRunAt");

CREATE TABLE IF NOT EXISTS "RecurringParticipant" (
  "RecurringParticipantID" BIGSERIAL PRIMARY KEY,
  "ScheduleID" BIGINT NOT NULL REFERENCES "RecurringSchedule"("RecurringScheduleID") ON DELETE CASCADE,
  "UserID" UUID NOT NULL REFERENCES "USER"("UserID") ON DELETE CASCADE,
  "PercentShare" NUMERIC(7,4),
  "FixedAmountMinor" BIGINT,
  "Active" BOOLEAN NOT NULL DEFAULT TRUE,
  CHECK (
    ("PercentShare" IS NOT NULL AND "FixedAmountMinor" IS NULL)
    OR ("PercentShare" IS NULL AND "FixedAmountMinor" IS NOT NULL)
  ),
  UNIQUE ("ScheduleID","UserID")
);

CREATE TABLE IF NOT EXISTS "RecurringRun" (
  "RecurringRunID" BIGSERIAL PRIMARY KEY,
  "ScheduleID" BIGINT NOT NULL REFERENCES "RecurringSchedule"("RecurringScheduleID") ON DELETE CASCADE,
  "RunAt" TIMESTAMPTZ NOT NULL,
  "Success" BOOLEAN NOT NULL,
  "DiagnosticMessage" TEXT
);
CREATE INDEX IF NOT EXISTS recurringrun_schedule_idx ON "RecurringRun" ("ScheduleID","RunAt");

CREATE TABLE IF NOT EXISTS "RecurringGeneratedExpense" (
  "RecurringGenExpenseID" BIGSERIAL PRIMARY KEY,
  "RunID" BIGINT NOT NULL REFERENCES "RecurringRun"("RecurringRunID") ON DELETE CASCADE,
  "ExpenseID" BIGINT NOT NULL REFERENCES "Expense"("ExpenseID") ON DELETE CASCADE,
  UNIQUE ("RunID","ExpenseID")
);

-- REMINDERS / NOTIFICATIONS
CREATE TABLE IF NOT EXISTS "ReminderPlan" (
  "ReminderPlanID" BIGSERIAL PRIMARY KEY,
  "ScopeType" reminder_scope_enum NOT NULL,
  "ScopeID" TEXT NOT NULL,
  "CreatedByUserID" UUID NOT NULL REFERENCES "USER"("UserID") ON DELETE RESTRICT,
  "Strategy" strategy_enum NOT NULL,
  "DefaultWindowDays" INT CHECK ("DefaultWindowDays" BETWEEN 1 AND 7),
  "TZ" TEXT NOT NULL,
  "Active" BOOLEAN NOT NULL DEFAULT TRUE,
  UNIQUE ("ScopeType","ScopeID")
);

CREATE TABLE IF NOT EXISTS "ReminderRule" (
  "ReminderRuleID" BIGSERIAL PRIMARY KEY,
  "ReminderPlanID" BIGINT NOT NULL REFERENCES "ReminderPlan"("ReminderPlanID") ON DELETE CASCADE,
  "OffsetBeforeDue" TEXT NOT NULL,  -- e.g., '7d','3d','1d','1h'
  "Channel" channel_enum NOT NULL,
  "MessageTemplateID" BIGINT REFERENCES "NotificationTemplate"("NotificationTemplateID") ON DELETE SET NULL,
  "CustomMessage" TEXT,
  "Position" INT NOT NULL
);
CREATE INDEX IF NOT EXISTS reminderrule_plan_idx ON "ReminderRule" ("ReminderPlanID","Position");

CREATE TABLE IF NOT EXISTS "ReminderInstance" (
  "ReminderInstanceID" BIGSERIAL PRIMARY KEY,
  "ReminderPlanID" BIGINT NOT NULL REFERENCES "ReminderPlan"("ReminderPlanID") ON DELETE CASCADE,
  "RuleID" BIGINT REFERENCES "ReminderRule"("ReminderRuleID") ON DELETE SET NULL,
  "ScheduledFor" TIMESTAMPTZ NOT NULL,
  "SentAt" TIMESTAMPTZ,
  "DeliveryStatus" TEXT,
  "ProviderMessageID" TEXT
);
CREATE INDEX IF NOT EXISTS reminderinstance_sched_idx
  ON "ReminderInstance" ("ScheduledFor","DeliveryStatus");

CREATE TABLE IF NOT EXISTS "NotificationTemplate" (
  "NotificationTemplateID" BIGSERIAL PRIMARY KEY,
  "Key" TEXT NOT NULL UNIQUE,
  "Title" TEXT NOT NULL,
  "Body" TEXT NOT NULL,
  "Variables" JSONB NOT NULL DEFAULT '[]'::jsonb,
  "Active" BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS "NotificationSetting" (
  "NotificationSettingID" BIGSERIAL PRIMARY KEY,
  "UserID" UUID NOT NULL REFERENCES "USER"("UserID") ON DELETE CASCADE,
  "AllowPush" BOOLEAN NOT NULL DEFAULT TRUE,
  "AllowEmail" BOOLEAN NOT NULL DEFAULT FALSE,
  "AllowInapp" BOOLEAN NOT NULL DEFAULT TRUE,
  "QuietHours" JSONB NOT NULL DEFAULT '{}'::jsonb,
  UNIQUE ("UserID")
);

-- USER ACCESS / SESSIONS
CREATE TABLE IF NOT EXISTS "UserAuthIdentity" (
  "UserAuthIdentityID" BIGSERIAL PRIMARY KEY,
  "UserID" UUID NOT NULL REFERENCES "USER"("UserID") ON DELETE CASCADE,
  "Type" TEXT NOT NULL CHECK ("Type" IN ('EMAIL','PHONE')),
  "Identifier" TEXT NOT NULL,
  "Verified" BOOLEAN NOT NULL DEFAULT FALSE,
  "VerifiedAt" TIMESTAMPTZ,
  "LastLoginAt" TIMESTAMPTZ,
  "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE ("Type","Identifier"),
  UNIQUE ("UserID","Type")
);

CREATE TABLE IF NOT EXISTS "UserOAuthProvider" (
  "UserOAuthProviderID" BIGSERIAL PRIMARY KEY,
  "UserID" UUID NOT NULL REFERENCES "USER"("UserID") ON DELETE CASCADE,
  "Provider" TEXT NOT NULL,
  "ProviderUserID" TEXT NOT NULL,
  "AccessTokenRef" TEXT,
  "RefreshTokenRef" TEXT,
  "ExpiresAt" TIMESTAMPTZ,
  UNIQUE ("Provider","ProviderUserID"),
  UNIQUE ("UserID","Provider")
);

CREATE TABLE IF NOT EXISTS "Session" (
  "SessionID" BIGSERIAL PRIMARY KEY,
  "UserID" UUID NOT NULL REFERENCES "USER"("UserID") ON DELETE CASCADE,
  "DeviceInfo" JSONB NOT NULL DEFAULT '{}'::jsonb,
  "IPHash" TEXT NOT NULL,
  "CreatedAt" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "RevokedAt" TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS session_user_idx ON "Session" ("UserID","CreatedAt");

-- OBSERVABILITY / SAFETY
CREATE TABLE IF NOT EXISTS "RateLimitCounter" (
  "RateLimitID" BIGSERIAL PRIMARY KEY,
  "UserID" UUID,
  "IPHash" TEXT,
  "ActionKey" TEXT NOT NULL,
  "WindowStart" TIMESTAMPTZ NOT NULL,
  "Count" INT NOT NULL DEFAULT 0 CHECK ("Count" >= 0),
  CHECK (("UserID" IS NOT NULL) OR ("IPHash" IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS ratelimit_window_idx ON "RateLimitCounter" ("ActionKey","WindowStart");

CREATE TABLE IF NOT EXISTS "BreachLock" (
  "BreachLockID" BIGSERIAL PRIMARY KEY,
  "UserID" UUID NOT NULL REFERENCES "USER"("UserID") ON DELETE CASCADE,
  "Reason" TEXT NOT NULL,
  "LockedUntil" TIMESTAMPTZ NOT NULL
);

-- SEARCH & TAGGING
CREATE TABLE IF NOT EXISTS "Tag" (
  "TagID" BIGSERIAL PRIMARY KEY,
  "Name" TEXT NOT NULL UNIQUE,
  "CreatedBy" UUID NOT NULL REFERENCES "USER"("UserID") ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS "ExpenseTag" (
  "ExpenseTagID" BIGSERIAL PRIMARY KEY,
  "ExpenseID" BIGINT NOT NULL REFERENCES "Expense"("ExpenseID") ON DELETE CASCADE,
  "TagID" BIGINT NOT NULL REFERENCES "Tag"("TagID") ON DELETE CASCADE,
  UNIQUE ("ExpenseID","TagID")
);

-- ============================================================
-- OPTIONAL: triggers to auto-update UpdatedAt/DateUpdated
-- (uncomment if you want automatic timestamp bumping)
-- ============================================================
-- CREATE OR REPLACE FUNCTION touch_updated_at() RETURNS trigger AS $$
-- BEGIN
--   NEW."UpdatedAt" := now();
--   RETURN NEW;
-- END; $$ LANGUAGE plpgsql;

-- CREATE TRIGGER tg_user_updated BEFORE UPDATE ON "USER"
-- FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- CREATE TRIGGER tg_bankaccount_updated BEFORE UPDATE ON "BANKACCOUNT"
-- FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- ... add similar triggers for other tables with UpdatedAt.
