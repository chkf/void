export type Result<T> =
  | { success: true; data: T }
  | { success: false; error: { code: string; message: string } };

export const ios: {
  system: {
    info(): Promise<Result<{ name: string; version: string; model: string }>>;
  };
};
