import { ios } from "@runtime/sdk";
import { Button, Form, Section, Text, render } from "@runtime/ui";

async function start() {
  render(<Text value="正在打开测试数据库" />);
  const table = await ios.graphics.execute({ sql: "CREATE TABLE IF NOT EXISTS notes (id INTEGER PRIMARY KEY, value TEXT)" });
  if (!table.success) { render(<Text value={table.error.code} />); return; }
  const rows = await ios.graphics.query({ sql: "SELECT value FROM notes WHERE id = 1" });
  if (!rows.success) { render(<Text value={rows.error.code} />); return; }
  const file = await ios.fs.exists({ path: "data/probe.txt" });
  const fileStatus = file.success ? "允许读取文件" : file.error.code;
  function show(status: string) {
    render(<Form><Section title="首次项目授权">
      <Text value={status} />
      <Text value={fileStatus} />
      <Button label="写入测试记录" onPress={async () => {
        const write = await ios.graphics.execute({ sql: "INSERT OR REPLACE INTO notes VALUES (1, '已读回测试记录')" });
        show(write.success ? "测试记录已保存" : write.error.code);
      }} />
    </Section></Form>);
  }
  show(rows.data.length ? String(rows.data[0].value) : "数据库已打开");
}

void start();
