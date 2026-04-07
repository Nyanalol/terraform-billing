# Diagrama de dependencias — BigQuery Billing

> Generado a partir del análisis de los ficheros SQL y Terraform del módulo `billing_datasets`.

## Leyenda de colores

| Color | Significado |
|---|---|
| 🔵 Azul claro | Tabla base en `BILLING_CLOUD_PLATFORM` |
| ⚪ Gris | Tabla lookup (semilla desde tfvars) |
| 🟣 Morado | Fuente externa (export de Google, Sheets, proyecto externo) |
| 🟠 Naranja | Scheduled Query |
| 🟡 Amarillo | Tabla gestionada por Talend (no Terraform) |
| 🟢 Verde | Vista BigQuery (definida en SQL de este proyecto) |

---

```mermaid
flowchart TD

    %% ─── Fuentes externas ────────────────────────────────────────────────────
    subgraph EXT["Fuentes externas"]
        direction LR
        GBE[/"Google Billing Export"/]
        SHEETS_WSF[/"Google Sheets\next_workspace_sku_sf"/]
        SPAIN_3P[/"ip-billing-prod\n.BILLING_CLOUD_PLATFORM\n.sku_third_party"/]
        TFVARS[/"terraform.tfvars\npayer_billing_accounts\ncurrency_symbols"/]
    end

    %% ─── BILLING_CLOUD_PLATFORM ──────────────────────────────────────────────
    subgraph BCP["📦 BILLING_CLOUD_PLATFORM"]
        direction TB
        RBDE["reseller_billing_detailed_export_v1"]
        EXT_WSF["ext_workspace_sku_sf\n(external / Sheets)"]
        GBM["gcp_billing_maps_sku"]
        MS["maps_services"]
        SKU3P_BCP["sku_third_party"]
        WSF["workspace_sku_sf"]
        CS["currency_symbols"]
        PBA["payer_billing_accounts"]
    end

    %% ─── third_party dataset ─────────────────────────────────────────────────
    subgraph TP["📦 third_party"]
        SKU3P_TP["sku_third_party"]
    end

    %% ─── Scheduled Queries ───────────────────────────────────────────────────
    subgraph SQ["⚙️ Scheduled Queries"]
        direction TB
        SQ_MS>/"maps_services.sql\n(día 1 y 2 de mes)"/]
        SQ_WSF>/"workspace_sku_sf.sql\n(domingos 00:00)"/]
        SQ_3P>/"sku_third_party_migration\n_from_spain.sql\n(lunes 07:30)"/]
    end

    %% ─── billing_views ───────────────────────────────────────────────────────
    subgraph BV["👁️ billing_views"]
        direction TB

        subgraph BV_TALEND["⚡ Gestionadas por Talend"]
            direction LR
            BA[["billing_accounts"]]
            BAF[["billing_accounts_full"]]
            ILT[["importes_lecturas_temp"]]
            ILBP[["importes_lecturas_by_project"]]
            ILA[["importes_lecturas_anuales"]]
            ILW[["importes_lecturas_workspace"]]
        end

        BGCP(["billing_gcp"])
        BGCPP(["billing_gcp_by_project"])
        BGMP(["billing_gmp"])
        BGMPP(["billing_gmp_by_project"])
        RV(["reseller_view"])
        SCPM(["sum_costs_credits_per_month"])
        SCPMBP(["sum_costs_credits_per_month\n_by_project"])
    end

    %% ─── looker_views ────────────────────────────────────────────────────────
    subgraph LV["📊 looker_views"]
        direction TB
        CGR(["consumos_google_reseller_factura"])
        CPA(["consumos_por_account"])
        CPPN(["consumos_por_proyecto_new"])
        CSF(["consumos_support_flex"])
        GBA(["gcp_billing_adjustment"])
        IL(["importes_lecturas"])
        VIL(["vista_importes_lecturas"])
    end

    %% ─── Edges: External → BCP ───────────────────────────────────────────────
    GBE          -->|billing export|    RBDE
    SHEETS_WSF   -->|external table|   EXT_WSF
    TFVARS       -->|seed BQ job|      PBA
    TFVARS       -->|seed BQ job|      CS

    %% ─── Edges: Scheduled Queries ────────────────────────────────────────────
    GBM          --> SQ_MS  -->|WRITE_TRUNCATE| MS
    EXT_WSF      --> SQ_WSF -->|WRITE_TRUNCATE| WSF
    SPAIN_3P     --> SQ_3P  -->|WRITE_TRUNCATE| SKU3P_TP

    %% ─── Edges: BCP → billing_views (vistas GCP) ─────────────────────────────
    RBDE         --> BGCP
    SKU3P_BCP    --> BGCP
    MS           --> BGCP
    PBA          --> BGCP

    RBDE         --> BGCPP
    SKU3P_BCP    --> BGCPP
    MS           --> BGCPP
    PBA          --> BGCPP

    %% ─── Edges: BCP → billing_views (vistas GMP) ─────────────────────────────
    RBDE         --> BGMP
    MS           --> BGMP
    PBA          --> BGMP

    RBDE         --> BGMPP
    SKU3P_BCP    --> BGMPP
    MS           --> BGMPP
    PBA          --> BGMPP

    %% ─── Edges: BCP → billing_views (reseller_view) ──────────────────────────
    RBDE         --> RV
    WSF          --> RV

    %% ─── Edges: billing_views → billing_views (agregados) ────────────────────
    BGCP         --> SCPM
    BGMP         --> SCPM

    BGCPP        --> SCPMBP
    BGMPP        --> SCPMBP

    %% ─── Edges: BCP/BV → looker_views ────────────────────────────────────────
    RBDE         --> CGR
    PBA          --> CGR

    SCPM         --> CPA
    BA           --> CPA

    SCPMBP       --> CPPN
    BA           --> CPPN

    RBDE         --> CSF
    BA           --> CSF
    PBA          --> CSF

    RBDE         --> GBA
    PBA          --> GBA

    ILT          --> IL
    ILBP         --> IL
    ILA          --> IL
    CS           --> IL

    ILT          --> VIL
    ILBP         --> VIL
    ILA          --> VIL
    CS           --> VIL

    %% ─── Estilos ─────────────────────────────────────────────────────────────
    classDef baseTable  fill:#c9dff5,stroke:#1a6dad,color:#000
    classDef lookup     fill:#e2e3e5,stroke:#5a6370,color:#000
    classDef external   fill:#e8d5f5,stroke:#6f42c1,color:#000
    classDef sq         fill:#fde8d8,stroke:#c96a1e,color:#000
    classDef talend     fill:#fff3cd,stroke:#c4980a,color:#000
    classDef view       fill:#d4edda,stroke:#218838,color:#000

    class RBDE,EXT_WSF,GBM,MS,SKU3P_BCP,WSF,SKU3P_TP baseTable
    class CS,PBA lookup
    class GBE,SHEETS_WSF,SPAIN_3P,TFVARS external
    class SQ_MS,SQ_WSF,SQ_3P sq
    class BA,BAF,ILT,ILBP,ILA,ILW talend
    class BGCP,BGCPP,BGMP,BGMPP,RV,SCPM,SCPMBP view
    class CGR,CPA,CPPN,CSF,GBA,IL,VIL view
```

---

## Resumen de dependencias por objeto

### `BILLING_CLOUD_PLATFORM` — tablas base

| Tabla | Origen de datos |
|---|---|
| `reseller_billing_detailed_export_v1` | Google Billing Export (automático) |
| `ext_workspace_sku_sf` | Google Sheets (tabla externa) |
| `gcp_billing_maps_sku` | Manual / pipeline externo |
| `maps_services` | Scheduled Query ← `gcp_billing_maps_sku` |
| `workspace_sku_sf` | Scheduled Query ← `ext_workspace_sku_sf` |
| `sku_third_party` | Manual / Talend (BCP copy) |
| `payer_billing_accounts` | Seed desde `terraform.tfvars` |
| `currency_symbols` | Seed desde `terraform.tfvars` |

### `third_party` — tablas base

| Tabla | Origen de datos |
|---|---|
| `sku_third_party` | Scheduled Query ← `ip-billing-prod.BILLING_CLOUD_PLATFORM.sku_third_party` |

### `billing_views` — vistas calculadas

| Vista | Depende de |
|---|---|
| `billing_gcp` | `reseller_billing_detailed_export_v1`, `sku_third_party`, `maps_services`, `payer_billing_accounts` |
| `billing_gcp_by_project` | `reseller_billing_detailed_export_v1`, `sku_third_party`, `maps_services`, `payer_billing_accounts` |
| `billing_gmp` | `reseller_billing_detailed_export_v1`, `maps_services`, `payer_billing_accounts` |
| `billing_gmp_by_project` | `reseller_billing_detailed_export_v1`, `sku_third_party`, `maps_services`, `payer_billing_accounts` |
| `reseller_view` | `reseller_billing_detailed_export_v1`, `workspace_sku_sf` |
| `sum_costs_credits_per_month` | `billing_gmp`, `billing_gcp` |
| `sum_costs_credits_per_month_by_project` | `billing_gmp_by_project`, `billing_gcp_by_project` |

### `billing_views` — tablas gestionadas por Talend (sin dependencias SQL en este proyecto)

`billing_accounts`, `billing_accounts_full`, `importes_lecturas_temp`, `importes_lecturas_by_project`, `importes_lecturas_anuales`, `importes_lecturas_workspace`

### `looker_views` — vistas de reporting

| Vista | Depende de |
|---|---|
| `consumos_google_reseller_factura` | `reseller_billing_detailed_export_v1`, `payer_billing_accounts` |
| `consumos_por_account` | `sum_costs_credits_per_month`, `billing_accounts` |
| `consumos_por_proyecto_new` | `sum_costs_credits_per_month_by_project`, `billing_accounts` |
| `consumos_support_flex` | `reseller_billing_detailed_export_v1`, `billing_accounts`, `payer_billing_accounts` |
| `gcp_billing_adjustment` | `reseller_billing_detailed_export_v1`, `payer_billing_accounts` |
| `importes_lecturas` | `importes_lecturas_temp`, `importes_lecturas_by_project`, `importes_lecturas_anuales`, `currency_symbols` |
| `vista_importes_lecturas` | `importes_lecturas_temp`, `importes_lecturas_by_project`, `importes_lecturas_anuales`, `currency_symbols` |
