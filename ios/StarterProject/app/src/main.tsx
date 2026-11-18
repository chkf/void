import { useState } from "react";
import { render, Form, Section, Text, TextField, Toggle } from "@runtime/ui";

function App() {
  const [name, setName] = useState("");
  const [showGreeting, setShowGreeting] = useState(true);

  return (
    <Form>
      <Section title="问候">
        <TextField label="你的名字" value={name} onChange={setName} />
        <Toggle label="显示问候" value={showGreeting} onChange={setShowGreeting} />
        {showGreeting && <Text value={name ? "你好，" + name : "你好"} />}
      </Section>
    </Form>
  );
}

render(<App />);
