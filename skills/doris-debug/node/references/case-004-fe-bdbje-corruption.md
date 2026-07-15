---
type: reference
category: node
keywords: [FE, BDBJE, startup failure, metadata corruption, .jdb, doris-meta, recovery]
---

# Case-004: FE BDBJE 元数据损坏导致无法启动

## Environment

- Doris version: all versions (BDBJE-based FE)
- Architecture: shared-nothing / cloud

## Symptom

FE 启动时退出，fe.log 显示：
```
java.io.FileNotFoundException: doris-meta/bdb/0000014d.jdb
  (No such file or directory)
```
或：
```
com.sleepycat.je.EnvironmentFailureException: ... Environment must be closed ...
java.lang.IllegalStateException: Environment is invalid
```

FE 进程启动后几秒自动退出。`SHOW FRONTENDS` 在其他节点上显示该 FE 状态为 `UNKNOWN` 或心跳超时。

## Investigation

### Step 1: 确认文件系统状态

```bash
ls -la fe/doris-meta/bdb/
# 查看 .jdb 文件列表，确认缺失的文件名

du -sh fe/doris-meta/bdb/
# 确认目录大小是否异常小（< 正常大小 = 可能被清空或损坏）

df -h fe/doris-meta/
# 确认磁盘是否曾经写满
```

常见场景：
- 磁盘写满 → BDBJE write 失败 → 日志文件不完整或缺失
- 异常关机（kill -9 / 断电）→ BDBJE 未完成 checkpoint → 日志文件损坏
- 人为误删 `doris-meta/bdb/` 中的文件

### Step 2: 确认集群状态

```sql
-- 在其他健康 FE 上执行
SHOW FRONTENDS\G
```

确认：
- 当前是否还有健康的 Master/Follower？
- 出问题的 FE 角色是什么（Master / Follower / Observer）？

**关键原则：永远不要删除最后一个健康 Master 的 doris-meta/ 目录。**

### Step 3: 恢复策略

#### 场景 A: 出问题的是 Follower 或 Observer

```
1. 从集群中移除该 FE:
   ALTER SYSTEM DROP FOLLOWER "bad_host:9010"
   或 ALTER SYSTEM DROP OBSERVER "bad_host:9010"

2. 停止该 FE 进程

3. 清空 doris-meta/:
   rm -rf fe/doris-meta/*

4. 重新加入集群:
   ALTER SYSTEM ADD FOLLOWER "bad_host:9010"
   # FE 会从 Master 自动同步元数据
```

#### 场景 B: 出问题的是 Master 但还有其他健康 Follower

```
1. 从集群中移除该 Master（集群会自动重新选主）
2. 清空该 FE 的 doris-meta/
3. 以 Follower 身份重新加入
```

#### 场景 C: 出问题的是唯一的 Master 且没有 Follower

```
⚠️ 最高风险场景
1. 先备份整个 fe/doris-meta/ 目录
2. 尝试 BDBJE recovery:
   java -jar je.jar DbRecover -h fe/doris-meta/bdb
3. 如果 recovery 失败，使用最近的元数据镜像:
   fe/doris-meta/image/ 中最新的 image 文件
4. 联系专业支持
```

## Root Cause

BDBJE 日志文件（.jdb）因磁盘满、异常关机、或人为误操作导致损坏或丢失。

## Fix

- **从健康副本恢复**: 如果有健康的 Follower/Observer，从其 rsync `doris-meta/`
- **BDBJE recovery**: 使用 Berkeley DB JE 的 recovery 工具（成功率取决于损坏程度）
- **预防**:
  1. 监控 FE 磁盘使用率，预留充足空间
  2. 至少配置 1 Follower + 1 Observer 实现高可用
  3. 定期备份 `fe/doris-meta/`
  4. 使用优雅关机（`kill -15` 而非 `kill -9`）

## Key diagnostic actions

1. `ls -la fe/doris-meta/bdb/` 确认文件完整性
2. `SHOW FRONTENDS` 确认集群还有哪些健康节点
3. 确认损坏 FE 的角色（Master/Follower/Observer）
4. 永远不要删除最后一个健康 Master 的 `doris-meta/`
5. 恢复前先备份现有的 `doris-meta/`
