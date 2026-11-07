-- ============================================================
-- 02_indexes.sql  显式索引
-- C1 产品数据管理（PDM）数字化系统 | MySQL 8.0.16+
-- 执行顺序：01 → 02 → 03 → 04 → 05 → 06
--
-- 说明：PRIMARY KEY / UNIQUE / FOREIGN KEY 三列由 MySQL 自动建立索引，
--       本文件只补「经常出现在 WHERE / ORDER BY / LIKE / GROUP BY 里，
--       但既不是主键也不是外键」的列，避免建立冗余索引。
--       可用 SHOW INDEX FROM 表名; 与 EXPLAIN 验证索引是否被命中。
--
-- 注意：本文件随 01 一起整体重跑（01 会 DROP 重建表，旧索引随之消失）。
--       若只想单独重跑本文件，请先执行下面注释掉的 DROP INDEX 语句。
-- ============================================================

USE pdm_db;

-- ---------- 产品与文档：按型号 / 系列 / 文档类型检索 ----------
CREATE INDEX idx_product_model      ON product(model);
CREATE INDEX idx_product_series     ON product(series);
CREATE INDEX idx_version_release    ON product_version(release_date);
CREATE INDEX idx_document_type      ON document(doc_type);
CREATE INDEX idx_document_author    ON document(author);

-- ---------- 物料：按名称模糊查询 ----------
CREATE INDEX idx_component_name     ON component(component_name);
CREATE INDEX idx_material_name      ON material(material_name);
CREATE INDEX idx_supplier_name      ON supplier(supplier_name);

-- ---------- 批次与追溯：按生产日期 / 批次号范围统计 ----------
CREATE INDEX idx_batch_prod_date      ON batch(production_date);
CREATE INDEX idx_instance_prod_date   ON product_instance(production_date);
CREATE INDEX idx_bcs_supplier         ON batch_component_source(supplier_id);
CREATE INDEX idx_bms_supplier         ON batch_material_source(supplier_id);

-- ---------- 单独重跑本文件时先执行以下语句 ----------
-- DROP INDEX idx_product_model      ON product;
-- DROP INDEX idx_product_series     ON product;
-- DROP INDEX idx_version_release    ON product_version;
-- DROP INDEX idx_document_type      ON document;
-- DROP INDEX idx_document_author    ON document;
-- DROP INDEX idx_component_name     ON component;
-- DROP INDEX idx_material_name      ON material;
-- DROP INDEX idx_supplier_name      ON supplier;
-- DROP INDEX idx_batch_prod_date    ON batch;
-- DROP INDEX idx_instance_prod_date ON product_instance;
-- DROP INDEX idx_bcs_supplier       ON batch_component_source;
-- DROP INDEX idx_bms_supplier       ON batch_material_source;

-- ---------- 验证：看索引清单与执行计划 ----------
SHOW INDEX FROM product;
EXPLAIN SELECT * FROM product WHERE model = 'X100';
