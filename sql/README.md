# 完整 SQL 源码 · 执行说明

**课程**：数据库综合课程设计　**选题**：C1 产品数据管理（PDM）数字化系统
**学生**：计科15班 张展梁 20240811　**指导老师**：田芳
**环境**：MySQL **8.0.16+**（`CHECK` 约束、ROLE 需要此版本以上），字符集 `utf8mb4`

> 本目录是「全套可运行 SQL 源码」，覆盖提交要求中的**建表、视图、索引、权限、数据插入、业务查询**六类代码。
> 仓库根目录的 `schema.sql` 是把 01/05/06 合并在一起的一体化脚本，二者内容等价，任选其一运行即可。

## 1. 文件清单

| 顺序 | 文件 | 内容 | 关键语句数 |
| --- | --- | --- | --- |
| 01 | `01_schema.sql` | 建库 `pdm_db`、DROP 旧表、**18 张表**及主键/外键/唯一/CHECK 约束 | 18 `CREATE TABLE` |
| 02 | `02_indexes.sql` | **显式索引**：针对常出现在 WHERE / ORDER BY 且无自动索引的列 | 12 `CREATE INDEX` |
| 03 | `03_views.sql` | **5 个业务视图**：文档、可供清单、供应商能力、批次供货明细、序列号溯源 | 5 `CREATE VIEW` |
| 04 | `04_privileges.sql` | **4 个账号 + 1 个角色**、按岗位授权、回收示例、授权验证 | 4 `CREATE USER` / 1 `CREATE ROLE` |
| 05 | `05_seed_data.sql` | **数据插入**：3 类产品、4 个批次、6 个序列号、5 家供应商等 | 18 `INSERT` / 122 行 |
| 06 | `06_business_queries.sql` | **业务查询**：设计文档、三种供货统计、缺陷溯源、权限查询、基于视图的简化查询 | 14 条 `SELECT` |

## 2. 执行顺序（必须按 01 → 06）

**方式 A｜MySQL Workbench（推荐）**
1. 双击连接进入编辑界面；
2. `File → Open SQL Script...` 打开 `01_schema.sql`，点 **⚡⚡（Execute All）**；
3. 依次打开并执行 `02`、`03`、`04`、`05`、`06`；
4. 每个文件执行完看下方 Output/Result Grid，最后一个文件会给出多组查询结果。

**方式 B｜命令行**

```bash
cd D:\GitHub\pdm-database\sql
mysql -u root -p < 01_schema.sql
mysql -u root -p < 02_indexes.sql
mysql -u root -p < 03_views.sql
mysql -u root -p < 04_privileges.sql
mysql -u root -p < 05_seed_data.sql
mysql -u root -p < 06_business_queries.sql
```

或在 `mysql>` 提示符里用 `source D:/GitHub/pdm-database/sql/01_schema.sql;`（路径用正斜杠）。

> `04_privileges.sql` 需要 root 或具备 `CREATE USER` / `GRANT` 权限的账号；若学校机房账号权限不足，**跳过 04 不影响 01–03、05–06 运行**，其余五份仍是完整可运行的 SQL 源码。

**重新运行**：从 `01` 从头开始整体重跑即可。`01` 开头会按「子表 → 父表」顺序 `DROP TABLE`，索引随之消失、视图先 `DROP VIEW IF EXISTS`，因此不会报 "already exists"。**不要单独重复执行 `02_indexes.sql`**（会提示 Duplicate key name），需要单跑时先解开该文件末尾注释掉的 `DROP INDEX` 语句。

## 3. 运行后验证清单

| 检查 | 语句 | 期望 |
| --- | --- | --- |
| 表 | `SHOW TABLES;` | 18 张用户表 |
| 视图 | `SHOW FULL TABLES FROM pdm_db WHERE Table_type = 'VIEW';` | 5 个视图 |
| 索引 | `SHOW INDEX FROM product;` | 含 `PRIMARY` 与 `idx_product_model` |
| 约束 | `SHOW CREATE TABLE batch_component_source;` | 有联合主键与复合外键 |
| 权限 | `SHOW GRANTS FOR 'pdm_qc'@'localhost';` | 只对单品表与溯源视图有 SELECT |
| 数据 | `SELECT COUNT(*) FROM product_instance;` | 6 |
| 查询 | 执行 `06` 各组 SELECT | 全部非空结果 |

**约束生效验证**（报错即正确）：解开 `06_business_queries.sql` 末尾 3 条注释 INSERT，应分别报
`ERROR 1062` 主键重复、`ERROR 1452` 复合外键失败、`ERROR 3819` CHECK 违规，可截图放进报告。

## 4. 对应题目条目

| 题目 | 落到哪里 |
| --- | --- |
| 1 产品类型/系列/型号/价格 | `01` 的 `product_type`、`product`；`05` 的 3 个型号 |
| 2 迭代版本与文档 | `01` 的 `product_version → document`；视图 `v_product_documents`；查询 1 |
| 3/4 产品↔部件 M:N | `01` 的 `product_component`（联合主键 + 用量） |
| 5/6 采购/自产 + 两层 BOM | `component.source_type` CHECK；`component_material` |
| 7 供应商↔物料 M:N | `component_supplier` / `material_supplier`；视图 `v_supply_catalog`；查询 2-A/2-B |
| 8 同批供货源相同 + 唯一序列号 | `batch` / `product_instance` / 两张 `batch_*_source`（联合主键） |
| 9 三类查询 | `06`：查询 1、2-A/2-B/2-C、3-①/②/③；视图 `v_serial_trace` |
| 总述「权限信息」 | `04` 数据库账号/角色 + `sys_role`/`sys_user`/`doc_permission` 应用表 |

## 5. 三个容易踩的坑

1. **插入顺序**：`batch_*_source` 带**复合外键**指向可供清单，所以 `05` 里必须先插 `component_supplier` / `material_supplier`，最后才插批次供货表，否则报 `ERROR 1452`。
2. **视图与子查询**：MySQL 视图定义不允许 `FROM (SELECT ...)` 这种派生表，所以 `03` 先用 `UNION ALL` 造明细视图、再基于它做 `GROUP BY`。
3. **笛卡尔积**：把两张「一对多」表同时 `LEFT JOIN` 到 `supplier` 会让行数相乘。`06` 的 2-A 改成「两张表先各自聚合再 JOIN」，加了金额求和也不会算错。

更详细的设计推导与逐步操作说明见仓库 `docs/01_需求分析与设计说明.md` 与 `docs/05_小白从零实验教程.md`。
