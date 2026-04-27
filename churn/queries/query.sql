WITH props_base AS (
    SELECT
        property_id,
        unit_id,
        created,
        acepta_mascotas,
        m2_utiles,
        edificio,
        sector_provincia,
        nombre_tipologia,
        first_time_rented,
        first_time_rp,
        actual_activa,
        ha_sido_arrendada,
        owner_id,
        monto_depto
    FROM bi_assetplan.bi_DimProperties
    WHERE unit_type = 'Appartment'
      AND mf = 0
      AND created >= '2024-01-01'
      AND sector_provincia IN (
            'Santiago - Centro', 'Santiago - Surponiente', 'Santiago - Nororiente',
            'Santiago - Sur', 'Santiago - Suroriente', 'Santiago - Norte', 'Santiago - Norponiente'
          )
),
schedules AS (
    SELECT 
    property_id, 
    MIN(schedule_date) AS schedule_date
    FROM bi_assetplan.bi_DimSchedules
    WHERE schedule_type_id = 2
    GROUP BY property_id
),
primer_contrato AS (
    SELECT 
    property_id, 
    renter_id,
    MIN(created_at) AS fecha_inicio,
    heredado
    FROM bi_assetplan.bi_DimContratos
    GROUP BY property_id
),
unidades_owner AS (
    SELECT 
    owner_id, 
    COUNT(unit_id) AS cantidad_unidades,
    monto_promedio_arrendadas_edificio
    FROM bi_assetplan.bi_DimProperties
    WHERE actual_activa = 1
    GROUP BY owner_id
),
churn_logic AS (
    -- Grouping the "No Churn" (Rented within 90 days)
    SELECT
        p.*,
        c.fecha_inicio AS event_date,
        0 AS churn
    FROM props_base p
    INNER JOIN primer_contrato c ON p.property_id = c.property_id
    WHERE p.ha_sido_arrendada = 'Si'
      AND DATEDIFF(c.fecha_inicio, p.created) <= 90
      AND c.heredado = 0
    UNION ALL
    -- Grouping the "Churn" (Left without renting within 90 days)
    SELECT
        p.*,
        fp.year_month_day AS event_date,
        1 AS churn
    FROM props_base p
    INNER JOIN bi_assetplan.bi_FactProperties fp ON fp.property_id = p.property_id
    WHERE p.ha_sido_arrendada = 'No'
      AND YEAR(p.first_time_rented) = 0
      AND fp.churn_unit_id_no_rented = 1
      AND fp.year_month_day >= '2024-01-01'
      AND DATEDIFF(fp.year_month_day, p.created) <= 90
),
selection AS (
SELECT 
    cl.*,
    s.schedule_date AS reception_date,
    u.cantidad_unidades AS owner_total_units,
    DATEDIFF(cl.event_date, cl.created) AS days_to_event
FROM churn_logic cl
LEFT JOIN schedules s ON cl.property_id = s.property_id
LEFT JOIN unidades_owner u ON cl.owner_id = u.owner_id
)
SELECT
	n.*,
	appep.precio_recomendado_ml
FROM selection n
LEFT JOIN bi_assetplan.aa_pmPricingExplainabilityPredictions appep 
	ON n.property_id = appep.property_id
WHERE days_to_event > 0
ORDER BY property_id, days_to_event