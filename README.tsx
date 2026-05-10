/** @jsxImportSource jsx-md */

import { readFileSync, readdirSync } from "fs";
import { join, resolve } from "path";

import {
  Heading, Paragraph, CodeBlock,
  Bold, Code, Link,
  Badge, Badges, Center, Section,
  List, Item,
} from "readme/src/components";

const REPO_DIR = resolve(import.meta.dirname);
const testDir = join(REPO_DIR, "test");
const testFiles = readdirSync(testDir).filter((f) => f.endsWith(".bats"));
const testCount = testFiles.reduce((sum, f) => {
  const content = readFileSync(join(testDir, f), "utf-8");
  return sum + (content.match(/@test /g)?.length ?? 0);
}, 0);

const readme = (
  <>
    <Center>
      <Heading level={1}>agenda</Heading>

      <Paragraph>
        <Bold>Read macOS Calendar data from a small command-line surface.</Bold>
      </Paragraph>

      <Paragraph>
        EventKit access for agents and humans: permission status, explicit access
        requests, calendar inventory, and upcoming events without opening Calendar.app.
      </Paragraph>

      <Badges>
        <Badge label="runtime" value="Swift + EventKit" color="f05138" logo="swift" logoColor="white" />
        <Badge label="shell" value="mise" color="7c3aed" href="https://mise.jdx.dev" />
        <Badge label="output" value="gum" color="ff69b4" href="https://github.com/charmbracelet/gum" />
        <Badge label="platform" value="macOS" color="blue" />
        <Badge label="tests" value={`${testCount} passing`} color="brightgreen" />
      </Badges>
    </Center>

    <Section title="Shape">
      <Paragraph>
        The read commands do not trigger the macOS permission prompt. Use{" "}
        <Code>agenda request-access</Code>{" "}when you want the prompt; use{" "}
        <Code>agenda status</Code>{" "}to inspect the current state safely.
      </Paragraph>

      <CodeBlock lang="bash">{`agenda status
agenda request-access
agenda calendar list
agenda calendar create --name agent/k7r2
agenda calendar list --json
agenda event list --days 14 --limit 20
agenda event create --calendar agent/k7r2 --title "Agenda follow-up" --start "2026-05-08 10:00"
agenda event prompt
agenda event delete --id EVENT_ID
agenda event list --calendar agent/k7r2 --json`}</CodeBlock>
    </Section>

    <Section title="Commands">
      <List>
        <Item><Code>status</Code> — show Calendar authorization state without prompting.</Item>
        <Item><Code>request-access</Code> — ask macOS for full EventKit calendar access.</Item>
        <Item><Code>calendar list</Code> — list readable calendars, sources, types, and writability.</Item>
        <Item><Code>calendar create</Code> — create a writable calendar if it does not already exist.</Item>
        <Item><Code>event list</Code> — list events from now through a configurable day window.</Item>
        <Item><Code>event create</Code> — create an event on a writable calendar.</Item>
        <Item><Code>event prompt</Code> — create an event interactively via gum prompts.</Item>
        <Item><Code>event delete</Code> — delete an event by identifier.</Item>
      </List>
    </Section>

    <Section title="Permission model">
      <Paragraph>
        Calendar access is attached to the terminal app that runs the command.
        If you run agenda from Terminal, iTerm, Ghostty, or an agent harness,
        macOS grants or denies that app. Denied access is fixed in System
        Settings → Privacy &amp; Security → Calendars.
      </Paragraph>

      <CodeBlock lang="bash">{`# Safe: never prompts
agenda status

# Intentional: may show the macOS permission prompt
agenda request-access

# Requires read access already granted
agenda event list --days 7`}</CodeBlock>
    </Section>

    <Section title="Output">
      <Paragraph>
        Human-readable output uses <Link href="https://github.com/charmbracelet/gum">gum</Link>{" "}
        tables and styled headings. Machine-readable output stays plain JSON.
      </Paragraph>
    </Section>

    <Section title="JSON for agents">
      <Paragraph>
        Every read surface that returns structured data accepts <Code>--json</Code>.
        Event timestamps are ISO-8601 strings; all-day events use <Code>YYYY-MM-DD</Code>.
      </Paragraph>

      <CodeBlock lang="bash">{`agenda status --json
agenda calendar list --json
agenda calendar create --name agent/k7r2 --json
agenda event create --calendar agent/k7r2 --title "Agenda follow-up" --start "2026-05-08 10:00" --json
agenda event delete --id EVENT_ID --json
agenda event list --days 3 --limit 10 --json`}</CodeBlock>
    </Section>

    <Section title="Development">
      <CodeBlock lang="bash">{`gh repo clone KnickKnackLabs/agenda
cd agenda
mise trust && mise install
mise run test
readme build --check`}</CodeBlock>

      <Paragraph>
        Tests use <Link href="https://github.com/bats-core/bats-core">BATS</Link> — {testCount} tests
        across {testFiles.length} suite{testFiles.length === 1 ? "" : "s"}. CI runs on macOS so the
        Swift source can typecheck against EventKit.
      </Paragraph>
    </Section>

    <Center>
      <Paragraph>
        README generated from <Code>README.tsx</Code> with{" "}
        <Link href="https://github.com/KnickKnackLabs/readme">readme</Link>.
      </Paragraph>
    </Center>
  </>
);

console.log(readme);
