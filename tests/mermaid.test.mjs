import test from 'node:test';
import assert from 'node:assert/strict';
import { mermaidUrl } from './load-core.mjs';
const mermaid = await import(mermaidUrl);

test('Mermaid lays out a top-down flowchart with shapes and a chain', () => {
  const diagram = mermaid.parseMermaid([
    'flowchart TD',
    'A[Start] --> B{OK?}',
    'B --> C(End)'
  ].join('\n'));
  assert.equal(diagram.direction, 'TD');
  assert.equal(diagram.nodes.length, 3);
  assert.deepEqual(diagram.nodes.map((node) => node.label), ['Start', 'OK?', 'End']);
  assert.deepEqual(diagram.nodes.map((node) => node.level), [0, 1, 2]);
  assert.equal(diagram.nodes[1].shape, 'diamond');
  assert.equal(diagram.edges.length, 2);
  assert.ok(diagram.width > 0 && diagram.height > diagram.nodes[0].height);
});

test('Mermaid keeps edge labels and left-to-right direction', () => {
  const diagram = mermaid.parseMermaid('graph LR\nA[One] -->|yes| B[Two]');
  assert.equal(diagram.direction, 'LR');
  assert.equal(diagram.edges[0].label, 'yes');
  assert.equal(diagram.nodes[0].x < diagram.nodes[1].x, true);
});

test('Mermaid rejects unsupported diagrams instead of guessing', () => {
  assert.equal(mermaid.parseMermaid('sequenceDiagram\nA->>B: hi'), undefined);
  assert.equal(mermaid.parseMermaid('flowchart TD\nsubgraph x\nA-->B\nend'), undefined);
  assert.equal(mermaid.parseMermaid('flowchart TD\nA[Broken --> B'), undefined);
  assert.equal(mermaid.parseMermaid(''), undefined);
});

test('Mermaid survives a cycle without looping forever', () => {
  const diagram = mermaid.parseMermaid('flowchart TD\nA --> B\nB --> A');
  assert.equal(diagram.nodes.length, 2);
  assert.equal(diagram.edges.length, 2);
  assert.ok(Number.isFinite(diagram.height));
});

test('Mermaid sequence keeps participants, messages and dashed arrows', () => {
  const sequence = mermaid.parseMermaidSequence([
    'sequenceDiagram',
    'participant A as Client',
    'A->>B: hello',
    'B-->>A: reply'
  ].join('\n'));
  assert.equal(sequence.participants.length, 2);
  assert.deepEqual(sequence.participants.map((item) => item.label), ['Client', 'B']);
  assert.equal(sequence.messages.length, 2);
  assert.equal(sequence.messages[0].dashed, false);
  assert.equal(sequence.messages[1].dashed, true);
  assert.ok(sequence.height > 100);
});

test('Mermaid sequence rejects unsupported control blocks', () => {
  assert.equal(mermaid.parseMermaidSequence('sequenceDiagram\nA->>B: hi\nalt ok\nB->>A: no\nend'), undefined);
  assert.equal(mermaid.parseMermaidSequence('sequenceDiagram'), undefined);
});

test('Mermaid class diagram keeps members and relations', () => {
  const diagram = mermaid.parseMermaidClass([
    'classDiagram',
    'class Animal {',
    '  +String name',
    '  +eat()',
    '}',
    'Animal <|-- Dog : inherits'
  ].join('\n'));
  assert.equal(diagram.classes.length, 2);
  assert.deepEqual(diagram.classes[0].members, ['+String name', '+eat()']);
  assert.equal(diagram.relations.length, 1);
  assert.equal(diagram.relations[0].label, 'inherits');
  assert.ok(diagram.height >= diagram.classes[0].height);
});

test('Mermaid class diagram rejects unclosed or unknown blocks', () => {
  assert.equal(mermaid.parseMermaidClass('classDiagram\nclass A {\n+x'), undefined);
  assert.equal(mermaid.parseMermaidClass('classDiagram\nnote for A "x"'), undefined);
});

test('Mermaid state diagram keeps named states, points and labels', () => {
  const diagram = mermaid.parseMermaidState([
    'stateDiagram-v2',
    '[*] --> Idle',
    'Idle --> Running : start',
    'Running --> [*]'
  ].join('\n'));
  assert.equal(diagram.nodes.length, 4);
  assert.equal(diagram.nodes[0].shape, 'point');
  assert.equal(diagram.nodes[3].shape, 'point');
  assert.equal(diagram.nodes[1].label, 'Idle');
  assert.equal(diagram.edges[1].label, 'start');
  assert.ok(diagram.height > 100);
});

test('Mermaid state diagram rejects notes and empty diagrams', () => {
  assert.equal(mermaid.parseMermaidState('stateDiagram-v2\nnote right of A: x'), undefined);
  assert.equal(mermaid.parseMermaidState('stateDiagram-v2'), undefined);
});
