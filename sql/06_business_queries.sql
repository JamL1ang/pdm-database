-- ============================================================
-- 06_business_queries.sql  业务查询（对应题目第 9 条）
-- 查询 1 设计文档 / 查询 2 三种统计 / 查询 3 缺陷溯源 / 权限查询
-- 末尾附「基于视图的简化查询」与 3 条约束验证语句
-- 依赖：05_seed_data.sql 已执行
-- ============================================================

USE pdm_db;

-- ============================================================
-- 三、查询（对应题目 9）
-- ============================================================

-- ---------- 查询 1：某个产品的设计文档（按迭代版本组织） ----------
SELECT p.model                AS 产品型号,
       pv.version_no          AS 产品版本,
       pv.release_date        AS 版本发布日期,
       d.doc_type             AS 文档类型,
       d.doc_rev              AS 文档修订号,
       d.title                AS 标题,
       d.author               AS 作者,
       d.update_date          AS 更新日期,
       d.file_path            AS 文件路径
FROM product p
JOIN product_version pv ON pv.product_id = p.product_id
JOIN document d         ON d.version_id  = pv.version_id
WHERE p.product_id = 1
ORDER BY pv.release_date, d.doc_type;

-- ---------- 查询 2：供应商供货情况统计（三种统计方式） ----------

-- 2-A 按供应商：统计可供的部件/材料种类数
-- 两张可供清单先各自聚合再 LEFT JOIN，避免原写法把行数相乘（笛卡尔积）
SELECT s.supplier_name                                    AS 供应商,
       COALESCE(c.cnt, 0)                                  AS 可供部件种类数,
       COALESCE(m.cnt, 0)                                  AS 可供材料种类数,
       COALESCE(c.cnt, 0) + COALESCE(m.cnt, 0)            AS 合计物料种类数
FROM supplier s
LEFT JOIN (SELECT supplier_id, COUNT(*) AS cnt FROM component_supplier GROUP BY supplier_id) c
       ON c.supplier_id = s.supplier_id
LEFT JOIN (SELECT supplier_id, COUNT(*) AS cnt FROM material_supplier  GROUP BY supplier_id) m
       ON m.supplier_id = s.supplier_id
ORDER BY 合计物料种类数 DESC, 供应商;

-- 2-B 按物料：统计每种物料有几家可选供应商（体现题目 7 的"多家供货"）
SELECT '部件' AS 物料类型, c.component_name AS 物料名称,
       COUNT(cs.supplier_id) AS 可选供应商数
FROM component c
JOIN component_supplier cs ON cs.component_id = c.component_id
GROUP BY c.component_id, c.component_name
UNION ALL
SELECT '材料', m.material_name, COUNT(ms.supplier_id)
FROM material m
JOIN material_supplier ms ON ms.material_id = m.material_id
GROUP BY m.material_id, m.material_name
ORDER BY 可选供应商数 DESC, 物料类型;

-- 2-C 按批次：统计各批次里每家供应商实际供了多少种物料
-- 与 2-A 的区别：2-A 是"能供什么"，2-C 是"这一批真的用了谁家的"
SELECT b.batch_no AS 批次号, p.model AS 产品型号,
       s.supplier_name AS 实际供应商,
       COUNT(DISTINCT x.item_key) AS 供货物料项数
FROM (
    SELECT batch_id, supplier_id, CONCAT('C', component_id) AS item_key FROM batch_component_source
    UNION ALL
    SELECT batch_id, supplier_id, CONCAT('M', material_id)  AS item_key FROM batch_material_source
) x
JOIN batch b    ON b.batch_id    = x.batch_id
JOIN product p  ON p.product_id  = b.product_id
JOIN supplier s ON s.supplier_id = x.supplier_id
GROUP BY b.batch_no, p.model, s.supplier_name
ORDER BY b.batch_no, 供货物料项数 DESC;

-- ---------- 查询 3：按出厂序列号追溯部件/材料的实际供应商 ----------
-- 思路：序列号 -> 批次 -> 批次供货表，再沿两层 BOM 展开
-- 自产部件本身没有采购供应商，其来源通过"材料层"体现，属正常现象

-- 3-① 部件层
SELECT pi.serial_no AS 出厂序列号, b.batch_no AS 批次号,
       c.component_name AS 部件, c.source_type AS 来源,
       COALESCE(s.supplier_name, '（自产件，见材料层）') AS 供应商
FROM product_instance pi
JOIN batch b              ON b.batch_id     = pi.batch_id
JOIN product_component pc ON pc.product_id  = pi.product_id
JOIN component c          ON c.component_id = pc.component_id
LEFT JOIN batch_component_source bcs
       ON bcs.batch_id = pi.batch_id AND bcs.component_id = pc.component_id
LEFT JOIN supplier s ON s.supplier_id = bcs.supplier_id
WHERE pi.serial_no = 'SN0001'
ORDER BY c.component_id;

-- 3-② 材料层（自产部件用的材料）
SELECT pi.serial_no AS 出厂序列号, b.batch_no AS 批次号,
       m.material_name AS 材料, s.supplier_name AS 供应商
FROM product_instance pi
JOIN batch b               ON b.batch_id      = pi.batch_id
JOIN product_component  pc ON pc.product_id   = pi.product_id
JOIN component_material cm ON cm.component_id = pc.component_id
JOIN material            m ON m.material_id   = cm.material_id
LEFT JOIN batch_material_source bms
       ON bms.batch_id = pi.batch_id AND bms.material_id = cm.material_id
LEFT JOIN supplier s ON s.supplier_id = bms.supplier_id
WHERE pi.serial_no = 'SN0001'
ORDER BY m.material_id;

-- 3-③ 两层合并：一次查出这台机器全部物料的实际供应商
SELECT x.出厂序列号, x.批次号, x.层级, x.物料名称, x.供应商
FROM (
    SELECT pi.serial_no AS 出厂序列号, b.batch_no AS 批次号,
           '部件' AS 层级, c.component_name AS 物料名称,
           COALESCE(s.supplier_name, '（自产件，见材料层）') AS 供应商
    FROM product_instance pi
    JOIN batch b              ON b.batch_id     = pi.batch_id
    JOIN product_component pc ON pc.product_id  = pi.product_id
    JOIN component c          ON c.component_id = pc.component_id
    LEFT JOIN batch_component_source bcs
           ON bcs.batch_id = pi.batch_id AND bcs.component_id = pc.component_id
    LEFT JOIN supplier s ON s.supplier_id = bcs.supplier_id
    UNION ALL
    SELECT pi.serial_no, b.batch_no, '材料', m.material_name,
           COALESCE(sm.supplier_name, '（未登记）')
    FROM product_instance pi
    JOIN batch b               ON b.batch_id      = pi.batch_id
    JOIN product_component  pc ON pc.product_id   = pi.product_id
    JOIN component_material cm ON cm.component_id = pc.component_id
    JOIN material            m ON m.material_id   = cm.material_id
    LEFT JOIN batch_material_source bms
           ON bms.batch_id = pi.batch_id AND bms.material_id = cm.material_id
    LEFT JOIN supplier sm ON sm.supplier_id = bms.supplier_id
) x
WHERE x.出厂序列号 = 'SN0001'
ORDER BY x.层级, x.物料名称;

-- 【动手验证】把上面 3-③ 的 'SN0001' 改成 'SN0003' 再跑一次：
--   同一型号 X100，外壳/显示屏/接头/芯片的供应商会变，因为两台机器分属不同批次。
--   这就是题目所说"探究产品缺陷产生原因"的数据依据。

-- ---------- 扩展查询：某角色能读哪些类型的文档（权限） ----------
SELECT u.username AS 用户, r.role_name AS 角色,
       dp.doc_type AS 文档类型, dp.can_read AS 可读, dp.can_write AS 可写
FROM sys_user u
JOIN sys_role r       ON r.role_id = u.role_id
JOIN doc_permission dp ON dp.role_id = r.role_id
WHERE u.username = 'wangwu'
ORDER BY dp.doc_type;

-- ---------- 附：约束验证（故意执行会报错，可截图放进报告） ----------
-- INSERT INTO product_instance VALUES ('SN0001', 1, 1, '2026-03-01');  -- 违反主键：序列号重复
-- INSERT INTO batch_component_source VALUES (3, 6, 5);                  -- 违反复合外键：自产件"接线"未登记过采购供应商
-- INSERT INTO component VALUES (7,'C007','摄像头','外协');                -- 违反 CHECK：来源只能采购/自产

-- ============================================================
-- 四、基于视图的简化查询（依赖 03_views.sql）
-- 同样的业务问题，用视图后 SQL 从十多行缩短到一两行，
-- 也便于按「视图」这个粒度做权限控制（见 04_privileges.sql）
-- ============================================================

-- 4-① 查某型号的全部设计文档（等价查询 1）
SELECT * FROM v_product_documents
WHERE 产品型号 = 'X100'
ORDER BY 版本发布日期, 文档类型;

-- 4-② 供应商可供能力排名（等价查询 2-A）
SELECT * FROM v_supplier_capability
ORDER BY 可供物料种类数 DESC;

-- 4-③ 按批次统计实际供货（等价查询 2-C）
SELECT b.batch_no AS 批次号,
       s.supplier_name AS 实际供应商,
       COUNT(DISTINCT x.item_key) AS 供货物料项数
FROM v_batch_supply_detail x
JOIN batch b    ON b.batch_id    = x.batch_id
JOIN supplier s ON s.supplier_id = x.supplier_id
GROUP BY b.batch_no, s.supplier_name
ORDER BY b.batch_no, 供货物料项数 DESC;

-- 4-④ 按序列号溯源（等价查询 3-③，本题核心）
SELECT 出厂序列号, 批次号, 层级, 物料名称, 供应商
FROM v_serial_trace
WHERE 出厂序列号 = 'SN0001'
ORDER BY 层级, 物料名称;

-- 4-⑤ 对照实验：同一型号、不同批次，供应商怎么变
SELECT 出厂序列号, 层级, 物料名称, 供应商
FROM v_serial_trace
WHERE 出厂序列号 IN ('SN0001','SN0003')
ORDER BY 物料名称, 出厂序列号;
