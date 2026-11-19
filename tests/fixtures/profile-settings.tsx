import { useState } from "react";
import { render, Theme, TabView, Tab, Screen, Form, Section, Button, Text, ProjectManagementButton } from "@runtime/ui";

const titles = ["训练", "历史", "进步", "模板", "我的"];
function Fitness() {
  const [tab, select] = useState("0");
  const [preferences, showPreferences] = useState(false);
  return <Theme mode="dark" dark={{ background: "#142821" }}>
    <TabView selection={tab} onChange={select}>
      {titles.map((title, i) => <Tab id={String(i)} title={title} systemName="circle">
        <Screen title={i === 4 && preferences ? "偏好" : title}>
          {i !== 4 ? <Text value={title + "内容"} /> : <Form>
            {preferences ? <Section title="应用">
              <ProjectManagementButton />
              <Button label="返回我的" onPress={() => showPreferences(false)} />
            </Section> : <Section title="个人资料">
              <Button label="偏好设置" onPress={() => showPreferences(true)} />
            </Section>}
          </Form>}
        </Screen>
      </Tab>)}
    </TabView>
  </Theme>;
}

render(<Fitness />);
