import Foundation
import CSQLite
import WorkdeskCore

func checkLegacyMigration(root: URL) async throws {
 try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
 var db: OpaquePointer?
 guard sqlite3_open(root.appendingPathComponent("workdesk.sqlite").path, &db) == SQLITE_OK else { throw StoreError.missing }
 let legacy = """
 PRAGMA user_version=1;
 CREATE TABLE projects(id TEXT PRIMARY KEY,title TEXT NOT NULL);
 CREATE TABLE tasks(id TEXT PRIMARY KEY,project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,title TEXT NOT NULL,status TEXT NOT NULL DEFAULT '待办',version INTEGER NOT NULL DEFAULT 1);
 INSERT INTO projects VALUES('old','旧版隔离项目');
 INSERT INTO tasks VALUES('done','old','历史完成','完成',7);
 INSERT INTO tasks VALUES('pending','old','尚未完成','待办',2);
 """
 let code = sqlite3_exec(db, legacy, nil, nil, nil)
 sqlite3_close(db)
 guard code == SQLITE_OK else { throw StoreError.database("legacy fixture failed") }
 let before = Date()
 let store = try Store(root: root)
 let migrated = try await store.tasks("old")
 guard let done = migrated.first(where: { $0.id == "done" }), let completed = done.completedAt else { throw StoreError.missing }
 try require(migrated.count == 2 && done.version == 7 && completed >= before && completed <= Date(), "旧 schema 迁移未使用迁移时间保守起算")
 try require(try await store.sweepArchive(now: completed.addingTimeInterval(43200 - 0.01)) == 0, "12h 边界前提前归档")
 try await store.updateTask(done.id, title: "完成后改名", status: "完成", expected: done.version)
 try require(try await store.tasks("old").first(where: { $0.id == done.id })?.completedAt == completed, "完成任务改名重置时间")
 try require(try await store.sweepArchive(now: completed.addingTimeInterval(43200)) == 1, "精确 12h 边界未归档")
 try require(try await store.projects().first?.status == "待办", "归档修改项目独立状态")
 let activeCount = try await store.tasks("old").count
 let archivedCount = try await store.archivedTasks("old").count
 try require(activeCount == 1 && archivedCount == 1, "归档前台数量不一致")
 let reopened = try Store(root: root)
 try require(try await reopened.archivedTasks("old").first?.completedAt == completed, "重开迁移重置归档时间")
 print("PASS actual v1 SQLite migration -> current schema; conservative timestamps, rename stability, exact 12h boundary, project state/count preservation")
}
