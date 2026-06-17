-- ─── DDL reference: payer_billing_accounts ───────────────────────────────────
-- Tabla de lookup que mapea cada payer_billing_account_id a un nombre de cuenta
-- legible. Todas las vistas de billing leen de esta tabla para calcular el campo
-- `account`, por lo que añadir o cambiar una cuenta solo requiere insertar o
-- actualizar una fila aquí — sin modificar ninguna vista ni hacer terraform apply.
--
-- Columnas:
--   payer_billing_account_id  STRING  → ID de la cuenta pagadora (clave)
--   account_name              STRING  → Nombre/etiqueta de negocio de la cuenta
--
-- Ejemplo de carga inicial:
-- INSERT INTO `<project>.BILLING_CLOUD_PLATFORM.payer_billing_accounts` VALUES
--   ('<PAYER_ID_1>', 'Cuenta Principal EUR'),
--   ('<PAYER_ID_2>', 'Cuenta Secundaria USD');
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE TABLE `@project_id.@dataset.payer_billing_accounts`
(
  payer_billing_account_id STRING NOT NULL OPTIONS(description = 'ID de la cuenta pagadora en el export de billing del revendedor'),
  account_name             STRING NOT NULL OPTIONS(description = 'Nombre o etiqueta de negocio de la cuenta')
)
OPTIONS(
  description = 'Lookup: mapeo de payer_billing_account_id a nombre de cuenta. Editar esta tabla para añadir/cambiar cuentas sin modificar las vistas.',
  labels      = [("managed_by", "terraform")]
);
