import { useState } from "react";
import { render, Theme, TabView, Tab, Screen, ScrollView, Card, Form, List, Section,
  VStack, HStack, Spacer, Text, Image, Button, TextField, Toggle, ProgressView } from "@runtime/ui";

function Components() {
  const [draft, setDraft] = useState("");
  const [value, setValue] = useState(0);
  return <Screen title="组件">
    <ScrollView>
      <Card cornerRadius={16} padding={16} border="secondaryText">
        <VStack alignment="leading" spacing={8}>
          <HStack spacing={8} alignment="center">
            <Image systemName="circle.grid.2x2" label="组件图标" size={22} color="accent" />
            <Text value="原生控件" font="headline" />
            <Spacer minLength={8} />
            <Text value={String(value) + " / 4"} weight="semibold" monospacedDigits color="secondaryText" />
          </HStack>
          <TextField label="临时文本" value={draft} onChange={setDraft} />
          <ProgressView value={value} total={4} label="示例进度" />
          <Button label="增加" icon="plus" variant="primary" fullWidth disabled={value >= 4} onPress={() => setValue(n => Math.min(4, n + 1))} />
          <Button label="复位" variant="secondary" disabled={value === 0} onPress={() => setValue(0)} />
        </VStack>
      </Card>
      {Array.from({ length: 36 }, (_, i) => <Text key={i} value={"滚动行 " + (i + 1)} />)}
    </ScrollView>
  </Screen>;
}

function Example() {
  const [selection, select] = useState("components");
  const [mode, setMode] = useState<"system" | "light" | "dark">("system");
  const [extra, showExtra] = useState(false);
  return <Theme mode={mode} light={{ accent: "#304C68" }} dark={{ accent: "#B8D5EF", onAccent: "#111923" }}>
    <TabView selection={selection} onChange={select}>
      <Tab id="components" title="组件" systemName="square.grid.2x2"><Components /></Tab>
      <Tab id="settings" title="设置" systemName="gearshape">
        <Screen title="设置">
          <Form appearance="themed">
            <Section title="主题">
              <Button label="跟随系统" onPress={() => setMode("system")} />
              <Button label="浅色" onPress={() => setMode("light")} />
              <Button label="深色" onPress={() => setMode("dark")} />
              <Text value={"模式 " + mode} color="secondaryText" />
            </Section>
            <Section title="导航">
              <Toggle label="第三个标签" value={extra} onChange={showExtra} />
            </Section>
          </Form>
        </Screen>
      </Tab>
      {extra && <Tab id="rows" title="列表" systemName="list.bullet">
        <Screen title="列表">
          <List appearance="themed">
            {Array.from({ length: 60 }, (_, i) => <Text key={i} value={"列表行 " + (i + 1)} font="body" />)}
          </List>
        </Screen>
      </Tab>}
    </TabView>
  </Theme>;
}

render(<Example />);
