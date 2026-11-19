import type { ComponentType, ReactNode } from "react";

export type ColorRole = "accent" | "background" | "surface" | "text" | "secondaryText" | "onAccent" | "success" | "warning" | "error";
/** Each supplied value is an opaque sRGB #RRGGBB. */
export type Palette = Partial<Record<ColorRole, string>>;
export type FontStyle = "largeTitle" | "title" | "title2" | "title3" | "headline" | "subheadline" | "body" | "callout" | "footnote" | "caption" | "caption2";
export type FontWeight = "light" | "regular" | "medium" | "semibold" | "bold" | "heavy";
export type Horizontal = "leading" | "center" | "trailing";
type Container<Props = {}> = ComponentType<Props & { children?: ReactNode }>;

export const Theme: Container<{ mode?: "system" | "light" | "dark"; light?: Palette; dark?: Palette }>;
export const TabView: ComponentType<{ selection: string; onChange: (id: string) => void; children: ReactNode }>;
export const Tab: ComponentType<{ id: string; title: string; systemName: string; children: ReactNode }>;
export const Screen: Container<{ title?: string }>;
export const ScrollView: Container;
export const Card: Container<{ background?: ColorRole; border?: ColorRole; borderWidth?: number; cornerRadius?: number; padding?: number }>;
export const VStack: Container<{ spacing?: number; alignment?: Horizontal }>;
export const HStack: Container<{ spacing?: number; alignment?: "top" | "center" | "bottom" | "firstTextBaseline" | "lastTextBaseline" }>;
export const Spacer: ComponentType<{ minLength?: number }>;
export const List: Container<{ appearance?: "system" | "themed" }>;
export const Form: Container<{ appearance?: "system" | "themed" }>;
export const Section: Container<{ title: string }>;
export const Text: ComponentType<{ value: string; font?: FontStyle; weight?: FontWeight; color?: ColorRole; alignment?: Horizontal; monospacedDigits?: boolean }>;
export const Image: ComponentType<{ systemName: string; label: string; size?: number; color?: ColorRole }>;
export const Button: ComponentType<{ label: string; onPress: () => void; icon?: string; variant?: "primary" | "secondary" | "plain" | "destructive"; disabled?: boolean; fullWidth?: boolean }>;
export const ProgressView: ComponentType<{ value: number; total?: number; label?: string }>;
export const TextField: ComponentType<{ label: string; value: string; onChange: (value: string) => void }>;
export const Toggle: ComponentType<{ label: string; value: boolean; onChange: (value: boolean) => void }>;
export const Picker: ComponentType<{ label: string; options: string[]; value: string; onChange: (value: string) => void }>;
export function render(view: ReactNode): void;
