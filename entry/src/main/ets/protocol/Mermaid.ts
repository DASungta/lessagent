// Native subset of Mermaid flowcharts. Anything outside this grammar returns
// undefined so the caller can keep showing the original code fence.

export interface MermaidNode {
  id: string;
  label: string;
  shape: string;
  level: number;
  order: number;
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface MermaidEdge {
  from: string;
  to: string;
  label: string;
  x1: number;
  y1: number;
  x2: number;
  y2: number;
}

export interface MermaidDiagram {
  direction: string;
  nodes: MermaidNode[];
  edges: MermaidEdge[];
  width: number;
  height: number;
}

export interface MermaidParticipant {
  id: string;
  label: string;
  x: number;
  width: number;
  lifeline: number;
}

export interface MermaidMessage {
  from: string;
  to: string;
  text: string;
  dashed: boolean;
  y: number;
  x1: number;
  x2: number;
}

export interface MermaidSequence {
  participants: MermaidParticipant[];
  messages: MermaidMessage[];
  width: number;
  height: number;
}

export interface MermaidClass {
  id: string;
  label: string;
  members: string[];
  level: number;
  order: number;
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface MermaidRelation {
  from: string;
  to: string;
  label: string;
  x1: number;
  y1: number;
  x2: number;
  y2: number;
}

export interface MermaidClassDiagram {
  classes: MermaidClass[];
  relations: MermaidRelation[];
  width: number;
  height: number;
}

const HEADER = /^(?:flowchart|graph)\s+(TD|TB|LR)\b/i;
const ARROW = /(-{2,3}>|==>|-\.->|---)/;
const NODE = /^([A-Za-z0-9_]+)\s*(?:\[(.*)\]|\(\((.*)\)\)|\((.*)\)|\{(.*)\})?$/;
const UNSUPPORTED = /^(?:subgraph|end|classDef|class\s|style\s|linkStyle|click\s|direction\s)/i;

const NODE_WIDTH = 132;
const NODE_HEIGHT = 54;
const GAP_X = 24;
const GAP_Y = 66;

function parseNode(raw: string): { id: string; label: string; shape: string } | undefined {
  const text = raw.trim();
  const match = NODE.exec(text);
  if (!match) return undefined;
  const id = match[1];
  const shape = match[2] !== undefined ? 'rect' : match[3] !== undefined ? 'circle' :
    match[4] !== undefined ? 'round' : match[5] !== undefined ? 'diamond' : 'rect';
  const rawLabel = match[2] ?? match[3] ?? match[4] ?? match[5] ?? '';
  const label = rawLabel.replace(/^"|"$/g, '').trim();
  return { id, label, shape };
}

export function parseMermaid(source: string): MermaidDiagram | undefined {
  const lines = source.replace(/\r\n?/g, '\n').split('\n').map((line: string) => line.trim())
    .filter((line: string) => line.length > 0 && !line.startsWith('%%'));
  if (lines.length === 0) return undefined;
  const header = HEADER.exec(lines[0]);
  if (!header) return undefined;
  const direction = header[1].toUpperCase() === 'LR' ? 'LR' : 'TD';

  const order: string[] = [];
  const labelOf: Record<string, string> = {};
  const shapeOf: Record<string, string> = {};
  const edges: { from: string; to: string; label: string }[] = [];
  const remember = (node: { id: string; label: string; shape: string }): void => {
    if (labelOf[node.id] === undefined) order.push(node.id);
    if (node.label) {
      labelOf[node.id] = node.label;
    } else if (labelOf[node.id] === undefined) {
      labelOf[node.id] = node.id;
    }
    if (node.shape !== 'rect' || shapeOf[node.id] === undefined) shapeOf[node.id] = node.shape;
  };

  for (let index = 1; index < lines.length; index += 1) {
    const line = lines[index];
    if (UNSUPPORTED.test(line)) return undefined;
    const parts = line.split(ARROW);
    if (parts.length === 1) {
      const single = parseNode(line);
      if (!single) return undefined;
      remember(single);
      continue;
    }
    let previous = parseNode(parts[0] ?? '');
    if (!previous) return undefined;
    remember(previous);
    for (let part = 1; part + 1 < parts.length; part += 2) {
      let tail = (parts[part + 1] ?? '').trim();
      let label = '';
      const labelled = /^\|([^|]*)\|\s*(.*)$/.exec(tail);
      if (labelled) {
        label = labelled[1].trim();
        tail = labelled[2];
      }
      const next = parseNode(tail);
      if (!next) return undefined;
      remember(next);
      edges.push({ from: previous.id, to: next.id, label: label });
      previous = next;
    }
  }
  if (order.length === 0) return undefined;
  return layoutGraph(order, labelOf, shapeOf, edges, direction);
}

function layoutGraph(order: string[], labelOf: Record<string, string>, shapeOf: Record<string, string>,
  edges: { from: string; to: string; label: string }[], direction: string): MermaidDiagram {
  // Breadth-first levels: back edges in a cycle are drawn but never lift an
  // already placed node, so a retry loop cannot stretch the diagram.
  const level: Record<string, number> = {};
  const incoming: Record<string, number> = {};
  for (const id of order) incoming[id] = 0;
  for (const edge of edges) if (edge.from !== edge.to && incoming[edge.to] !== undefined) incoming[edge.to] += 1;
  const queue: string[] = order.filter((id: string) => incoming[id] === 0);
  if (queue.length === 0) queue.push(order[0]);
  for (const id of queue) level[id] = 0;
  for (let head = 0; head < queue.length; head += 1) {
    const current = queue[head];
    for (const edge of edges) {
      if (edge.from !== current || level[edge.to] !== undefined) continue;
      level[edge.to] = level[current] + 1;
      queue.push(edge.to);
    }
  }
  for (const id of order) if (level[id] === undefined) level[id] = 0;

  const perLevel: Record<number, number> = {};
  const nodes: MermaidNode[] = [];
  for (const id of order) {
    const slot = perLevel[level[id]] ?? 0;
    perLevel[level[id]] = slot + 1;
    const point = shapeOf[id] === 'point';
    nodes.push({
      id: id, label: labelOf[id], shape: shapeOf[id], level: level[id], order: slot,
      x: 0, y: 0, width: point ? 24 : NODE_WIDTH, height: point ? 24 : NODE_HEIGHT
    });
  }
  const maxLevel = Math.max(...nodes.map((node: MermaidNode) => node.level));
  let maxSlot = 0;
  for (const key of Object.keys(perLevel)) maxSlot = Math.max(maxSlot, perLevel[Number(key)]);
  let width = 0;
  let height = 0;
  if (direction === 'LR') {
    width = (maxLevel + 1) * (NODE_WIDTH + GAP_X + 20) + 20;
    height = maxSlot * (NODE_HEIGHT + 28) + 20;
  } else {
    width = maxSlot * (NODE_WIDTH + GAP_X) + 20;
    height = (maxLevel + 1) * (NODE_HEIGHT + GAP_Y) + 20;
  }
  for (const node of nodes) {
    if (direction === 'LR') {
      node.x = 20 + node.level * (NODE_WIDTH + GAP_X + 20);
      node.y = 20 + node.order * (NODE_HEIGHT + 28);
    } else {
      node.x = 20 + node.order * (NODE_WIDTH + GAP_X);
      node.y = 20 + node.level * (NODE_HEIGHT + GAP_Y);
    }
  }
  const byId: Record<string, MermaidNode> = {};
  for (const node of nodes) byId[node.id] = node;
  const rendered: MermaidEdge[] = edges.map((edge) => {
    const from = byId[edge.from];
    const to = byId[edge.to];
    if (direction === 'LR') {
      return { from: edge.from, to: edge.to, label: edge.label,
        x1: from.x + from.width, y1: from.y + from.height / 2,
        x2: to.x, y2: to.y + to.height / 2 };
    }
    return { from: edge.from, to: edge.to, label: edge.label,
      x1: from.x + from.width / 2, y1: from.y + from.height,
      x2: to.x + to.width / 2, y2: to.y };
  });
  return { direction: direction, nodes: nodes, edges: rendered, width: width, height: height };
}

const PARTICIPANT = /^participant\s+([A-Za-z0-9_]+)(?:\s+as\s+(.+))?$/i;
const MESSAGE = /^([A-Za-z0-9_]+)\s*(-->>|->>|-->|->)\s*([A-Za-z0-9_]+)\s*:\s*(.*)$/;

export function parseMermaidSequence(source: string): MermaidSequence | undefined {
  const lines = source.replace(/\r\n?/g, '\n').split('\n').map((line: string) => line.trim())
    .filter((line: string) => line.length > 0 && !line.startsWith('%%'));
  if (lines.length < 2 || !/^sequenceDiagram\b/i.test(lines[0])) return undefined;

  const order: string[] = [];
  const labels: Record<string, string> = {};
  const messages: { from: string; to: string; text: string; dashed: boolean }[] = [];
  const remember = (id: string, label: string = ''): void => {
    if (labels[id] === undefined) order.push(id);
    if (label) labels[id] = label;
    else if (labels[id] === undefined) labels[id] = id;
  };

  for (let index = 1; index < lines.length; index += 1) {
    const line = lines[index];
    const participant = PARTICIPANT.exec(line);
    if (participant) {
      remember(participant[1], (participant[2] ?? '').trim());
      continue;
    }
    const message = MESSAGE.exec(line);
    if (message) {
      remember(message[1]);
      remember(message[3]);
      messages.push({ from: message[1], to: message[3], text: message[4].trim(),
        dashed: message[2].startsWith('--') });
      continue;
    }
    return undefined;
  }
  if (messages.length === 0) return undefined;

  const participants: MermaidParticipant[] = [];
  for (let index = 0; index < order.length; index += 1) {
    const x = 20 + index * 150;
    participants.push({ id: order[index], label: labels[order[index]], x: x, width: 120,
      lifeline: x + 60 });
  }
  const byId: Record<string, MermaidParticipant> = {};
  for (const participant of participants) byId[participant.id] = participant;
  const rendered: MermaidMessage[] = messages.map((message, index: number) => ({
    from: message.from, to: message.to, text: message.text, dashed: message.dashed,
    y: 96 + index * 58, x1: byId[message.from].lifeline, x2: byId[message.to].lifeline
  }));
  return {
    participants: participants,
    messages: rendered,
    width: 20 + order.length * 150,
    height: 96 + messages.length * 58 + 40
  };
}

const CLASS_OPEN = /^class\s+([A-Za-z0-9_]+)\s*\{?$/;
const RELATION = /^([A-Za-z0-9_]+)\s*(<\|--|--\|>|\*--|--\*|o--|--o|\.\.>|<\.\.|-->|<--)\s*([A-Za-z0-9_]+)\s*(?::\s*(.*))?$/;
const CLASS_WIDTH = 168;
const CLASS_MEMBER_HEIGHT = 18;
const CLASS_GAP_X = 30;
const CLASS_GAP_Y = 60;

function classHeight(members: string[]): number {
  return 40 + Math.min(members.length, 6) * CLASS_MEMBER_HEIGHT;
}

export function parseMermaidClass(source: string): MermaidClassDiagram | undefined {
  const lines = source.replace(/\r\n?/g, '\n').split('\n').map((line: string) => line.trim())
    .filter((line: string) => line.length > 0 && !line.startsWith('%%'));
  if (lines.length < 2 || !/^classDiagram\b/i.test(lines[0])) return undefined;

  const order: string[] = [];
  const members: Record<string, string[]> = {};
  const relations: { from: string; to: string; label: string }[] = [];
  const remember = (id: string): void => {
    if (members[id] === undefined) {
      members[id] = [];
      order.push(id);
    }
  };

  for (let index = 1; index < lines.length; index += 1) {
    const line = lines[index];
    const open = CLASS_OPEN.exec(line);
    if (open) {
      remember(open[1]);
      if (line.endsWith('{')) {
        index += 1;
        while (index < lines.length && lines[index] !== '}') {
          const member = lines[index];
          if (member.startsWith('class ')) return undefined;
          members[open[1]].push(member);
          index += 1;
        }
        if (index >= lines.length) return undefined;
      }
      continue;
    }
    const relation = RELATION.exec(line);
    if (relation) {
      remember(relation[1]);
      remember(relation[3]);
      relations.push({ from: relation[1], to: relation[3], label: (relation[4] ?? '').trim() });
      continue;
    }
    if (/^class\s/.test(line)) return undefined;
    if (line === '}') continue;
    if (/^(?:direction|note|click|style)\b/i.test(line)) return undefined;
    return undefined;
  }
  if (order.length === 0) return undefined;

  const level: Record<string, number> = {};
  const incoming: Record<string, number> = {};
  for (const id of order) incoming[id] = 0;
  for (const relation of relations) if (relation.from !== relation.to) incoming[relation.to] += 1;
  const queue: string[] = order.filter((id: string) => incoming[id] === 0);
  if (queue.length === 0) queue.push(order[0]);
  for (const id of queue) level[id] = 0;
  for (let head = 0; head < queue.length; head += 1) {
    for (const relation of relations) {
      if (relation.from !== queue[head] || level[relation.to] !== undefined) continue;
      level[relation.to] = level[queue[head]] + 1;
      queue.push(relation.to);
    }
  }
  for (const id of order) if (level[id] === undefined) level[id] = 0;

  const perLevel: Record<number, number> = {};
  const classes: MermaidClass[] = [];
  for (const id of order) {
    const slot = perLevel[level[id]] ?? 0;
    perLevel[level[id]] = slot + 1;
    classes.push({ id: id, label: id, members: members[id], level: level[id], order: slot,
      x: 20 + slot * (CLASS_WIDTH + CLASS_GAP_X), y: 0,
      width: CLASS_WIDTH, height: classHeight(members[id]) });
  }
  const maxLevel = Math.max(...classes.map((item: MermaidClass) => item.level));
  const levelHeight: Record<number, number> = {};
  for (const item of classes) {
    levelHeight[item.level] = Math.max(levelHeight[item.level] ?? 0, item.height);
  }
  const levelY: Record<number, number> = {};
  let nextY = 20;
  for (let current = 0; current <= maxLevel; current += 1) {
    levelY[current] = nextY;
    nextY += (levelHeight[current] ?? 88) + CLASS_GAP_Y;
  }
  for (const item of classes) item.y = levelY[item.level];
  let maxSlot = 0;
  for (const key of Object.keys(perLevel)) maxSlot = Math.max(maxSlot, perLevel[Number(key)]);
  const width = maxSlot * (CLASS_WIDTH + CLASS_GAP_X) + 20;
  const height = nextY - CLASS_GAP_Y + 20;
  const byId: Record<string, MermaidClass> = {};
  for (const item of classes) byId[item.id] = item;
  const rendered: MermaidRelation[] = relations.map((relation) => {
    const from = byId[relation.from];
    const to = byId[relation.to];
    return { from: relation.from, to: relation.to, label: relation.label,
      x1: from.x + from.width / 2, y1: from.y + from.height,
      x2: to.x + to.width / 2, y2: to.y };
  });
  return { classes: classes, relations: rendered, width: width, height: height };
}

const STATE_HEADER = /^stateDiagram(?:-v2)?\b/i;
const STATE_TRANSITION = /^(\[\*\]|[A-Za-z0-9_]+)\s*-->\s*(\[\*\]|[A-Za-z0-9_]+)\s*(?::\s*(.*))?$/;
const STATE_DECLARE = /^state\s+"?([^"]+)"?(?:\s+as\s+([A-Za-z0-9_]+))?$/;

export function parseMermaidState(source: string): MermaidDiagram | undefined {
  const lines = source.replace(/\r\n?/g, '\n').split('\n').map((line: string) => line.trim())
    .filter((line: string) => line.length > 0 && !line.startsWith('%%'));
  if (lines.length < 2 || !STATE_HEADER.test(lines[0])) return undefined;

  const order: string[] = [];
  const labelOf: Record<string, string> = {};
  const shapeOf: Record<string, string> = {};
  const edges: { from: string; to: string; label: string }[] = [];
  const remember = (id: string, label: string, shape: string): void => {
    if (labelOf[id] === undefined) order.push(id);
    if (label) labelOf[id] = label;
    else if (labelOf[id] === undefined) labelOf[id] = id;
    if (shape !== 'round' || shapeOf[id] === undefined) shapeOf[id] = shape;
  };
  const endpoint = (raw: string, source: boolean): { id: string; label: string; shape: string } => {
    if (raw === '[*]') return { id: source ? '__start' : '__end', label: '●', shape: 'point' };
    return { id: raw, label: '', shape: 'round' };
  };

  for (let index = 1; index < lines.length; index += 1) {
    const line = lines[index];
    const transition = STATE_TRANSITION.exec(line);
    if (transition) {
      const from = endpoint(transition[1], true);
      const to = endpoint(transition[2], false);
      remember(from.id, from.label, from.shape);
      remember(to.id, to.label, to.shape);
      edges.push({ from: from.id, to: to.id, label: (transition[3] ?? '').trim() });
      continue;
    }
    const declare = STATE_DECLARE.exec(line);
    if (declare) {
      const id = (declare[2] ?? declare[1]).trim();
      remember(id, declare[2] ? declare[1].trim() : '', 'round');
      continue;
    }
    return undefined;
  }
  if (order.length === 0 || edges.length === 0) return undefined;
  return layoutGraph(order, labelOf, shapeOf, edges, 'TD');
}
