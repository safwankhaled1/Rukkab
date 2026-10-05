export function localLabel(text: string, en: boolean) {
  const parts = text.split("|");
  return parts[en ? 1 : 0] ?? parts[0];
}
