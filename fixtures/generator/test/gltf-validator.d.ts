// Minimal types for the Khronos glTF-Validator npm package (it ships none).

declare module "gltf-validator" {
  interface ValidatorOptions {
    uri?: string;
    maxIssues?: number;
    externalResourceFunction?: (uri: string) => Promise<Uint8Array>;
  }
  interface ValidatorReport {
    issues: {
      numErrors: number;
      numWarnings: number;
      messages: Array<{ code: string; message: string; severity: number; pointer?: string }>;
    };
  }
  const validator: {
    validateBytes(data: Uint8Array, options?: ValidatorOptions): Promise<ValidatorReport>;
  };
  export default validator;
}
