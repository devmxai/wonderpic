export function firstRow<T>(data: T[] | null | undefined): T {
  if (!data || data.length == 0) {
    throw new Error('RPC returned empty result');
  }
  return data[0];
}
