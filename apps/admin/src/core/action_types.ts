import type { Row } from "../data";
export type Action = {
  label: string;
  action: string;
  rpc?: string;
  fields?: string[];
  fixed?: Row;
};
