# Visual acceptance

Readable text with **bold**, `inline code`, and a long table.

| Feature | Expected result | Evidence |
| --- | --- | --- |
| Long cell | This is a deliberately long description that should wrap inside its column without clipping. | Device inspection |

```typescript
const message = "This long code line must remain readable and scroll horizontally without losing glyphs or blocking the composer.";
console.log(message);
```

<details><summary>Details</summary>

Expanded details remain selectable.

</details>
