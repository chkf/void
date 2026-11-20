import { useState } from "react";
import { Button, ProjectManagementButton, Screen, ScrollView, Tab, TabView, Text, TextField, Theme, render } from "@runtime/ui";

function Sample() {
  const [mode, setMode] = useState<"system" | "light" | "dark">("system");
  const [alternate, setAlternate] = useState(false);
  const [themed, setThemed] = useState(true);
  const [tabs, setTabs] = useState(true);
  const [selected, select] = useState("sample");
  const [draft, edit] = useState("");
  const settings = <Screen title="Appearance"><ScrollView>
    <Button label="System" onPress={() => setMode("system")} />
    <Button label="Light" onPress={() => setMode("light")} />
    <Button label="Dark" onPress={() => setMode("dark")} />
    <Button label="Change palette" onPress={() => setAlternate(value => !value)} />
    <Button label="Toggle tabs" onPress={() => setTabs(value => !value)} />
    <Button label="Toggle theme" onPress={() => setThemed(value => !value)} />
    <ProjectManagementButton />
  </ScrollView></Screen>;
  const content = tabs ? <TabView selection={selected} onChange={select}>
    <Tab id="sample" title="Sample" systemName="square">
      <Screen title="Sample screen"><ScrollView>
        <TextField label="Draft" value={draft} onChange={edit} />
        {Array.from({ length: 48 }, (_, i) => <Text key={i} value={"Row " + i} />)}
      </ScrollView></Screen>
    </Tab>
    <Tab id="settings" title="Settings" systemName="gearshape">{settings}</Tab>
  </TabView> : settings;
  return themed ? <Theme mode={mode}
    dark={{ background: alternate ? "#482D54" : "#204858" }}
    light={{ background: alternate ? "#FFE4B8" : "#C8E8E0" }}>{content}</Theme> : content;
}

render(<Sample />);
