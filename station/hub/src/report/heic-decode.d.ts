// Types of heic-decode@2.1.0 (the package ships none): decodes the primary image of a HEIC/HEIF
// file to RGBA pixels.
declare module "heic-decode" {
  interface DecodedImage {
    readonly width: number;
    readonly height: number;
    /** RGBA, 4 bytes per pixel, row by row. */
    readonly data: Uint8ClampedArray;
  }
  function decode(options: { buffer: Uint8Array | ArrayBuffer }): Promise<DecodedImage>;
  export default decode;
}
