import type { ComponentType, ReactNode } from "react";

type Container = ComponentType<{ children?: ReactNode }>;
export const VStack: Container;
export const HStack: Container;
export const List: Container;
export const Form: Container;
export const Section: ComponentType<{ title: string; children?: ReactNode }>;
export const Text: ComponentType<{ value: string }>;
export const Image: ComponentType<{ systemName: string; label: string }>;
export const Button: ComponentType<{ label: string; onPress: () => void }>;
export const ProjectManagementButton: ComponentType<{}>;
export const TextField: ComponentType<{ label: string; value: string; onChange: (value: string) => void }>;
export const Toggle: ComponentType<{ label: string; value: boolean; onChange: (value: boolean) => void }>;
export const Picker: ComponentType<{ label: string; options: string[]; value: string; onChange: (value: string) => void }>;
export function render(view: ReactNode): void;
