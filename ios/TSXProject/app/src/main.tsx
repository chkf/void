import { useState } from "react";
import { render, Form, Section, Text, TextField, Toggle, Button, ProjectManagementButton } from "@runtime/ui";

function App() {
  const [name, setName] = useState("");
  const [showGreeting, setShowGreeting] = useState(true);
  const [settings, setSettings] = useState(false);

  if (settings) return (
    <Form><Section title="设置">
      <ProjectManagementButton />
      <Button label="返回" onPress={() => setSettings(false)} />
    </Section></Form>
  );

  return (
    <Form>
      <Section title="问候">
        <TextField label="你的名字" value={name} onChange={setName} />
        <Toggle label="显示问候" value={showGreeting} onChange={setShowGreeting} />
        {showGreeting && <Text value={name ? "你好，" + name : "你好"} />}
      </Section>
      <Section title="应用"><Button label="设置" onPress={() => setSettings(true)} /></Section>
    </Form>
  );
}

render(<App />);
