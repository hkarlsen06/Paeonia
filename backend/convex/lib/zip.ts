// A small ZIP writer for the data export. It writes one archive in memory, with UTF-8 file names and
// no ZIP64, so an archive stays under 4 GB and 65,535 files. The export splits larger archives into
// parts long before that. Each file is stored as it is or deflated.

const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n += 1) {
    let c = n;
    for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c >>> 0;
  }
  return table;
})();

/** The CRC-32 of `bytes`, as ZIP stores it. */
export function crc32(bytes: Uint8Array): number {
  let crc = 0xffffffff;
  for (let i = 0; i < bytes.length; i += 1) crc = CRC_TABLE[(crc ^ bytes[i]!) & 0xff]! ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}

/** Raw deflate, which is what the ZIP "deflated" method holds. */
export async function deflateRaw(bytes: Uint8Array): Promise<Uint8Array> {
  const stream = new Blob([bytes as BlobPart]).stream().pipeThrough(new CompressionStream("deflate-raw"));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

type CentralEntry = {
  name: Uint8Array;
  method: 0 | 8;
  crc: number;
  compressedSize: number;
  size: number;
  offset: number;
  dosTime: number;
  dosDate: number;
};

function dosDateTime(date: Date): { dosTime: number; dosDate: number } {
  const year = Math.min(Math.max(date.getUTCFullYear(), 1980), 2107);
  return {
    dosTime: (date.getUTCHours() << 11) | (date.getUTCMinutes() << 5) | (date.getUTCSeconds() >> 1),
    dosDate: ((year - 1980) << 9) | ((date.getUTCMonth() + 1) << 5) | date.getUTCDate(),
  };
}

const encoder = new TextEncoder();
const UTF8_FLAG = 0x0800;

export class ZipBuilder {
  private readonly parts: BlobPart[] = [];
  private readonly entries: CentralEntry[] = [];
  private offset = 0;

  constructor(private readonly modified: Date = new Date()) {}

  get fileCount(): number {
    return this.entries.length;
  }

  /** The bytes written so far, not counting the directory that `toBlob` adds. */
  get byteLength(): number {
    return this.offset;
  }

  /**
   * Adds a file. `compress` deflates it when that makes it smaller. Photos and voice messages are
   * already compressed, so the export passes false for them.
   */
  async addFile(name: string, data: Uint8Array, options: { compress: boolean }): Promise<void> {
    const crc = crc32(data);
    if (options.compress && data.length > 128) {
      const deflated = await deflateRaw(data);
      if (deflated.length < data.length) {
        this.write(name, 8, crc, deflated, data.length);
        return;
      }
    }
    this.write(name, 0, crc, data, data.length);
  }

  /** Adds a file whose CRC-32 is known, without reading the bytes again. */
  addStoredBlob(name: string, blob: Blob, crc: number): void {
    this.write(name, 0, crc, blob, blob.size);
  }

  /** Adds a file that is already deflated. `size` and `crc` are those of the bytes before deflating. */
  addDeflatedBlob(name: string, blob: Blob, crc: number, size: number): void {
    this.write(name, 8, crc, blob, size);
  }

  private write(name: string, method: 0 | 8, crc: number, data: Uint8Array | Blob, size: number): void {
    const nameBytes = encoder.encode(name);
    const compressedSize = data instanceof Blob ? data.size : data.length;
    const { dosTime, dosDate } = dosDateTime(this.modified);
    const header = new Uint8Array(30 + nameBytes.length);
    const view = new DataView(header.buffer);
    view.setUint32(0, 0x04034b50, true);
    view.setUint16(4, 20, true);
    view.setUint16(6, UTF8_FLAG, true);
    view.setUint16(8, method, true);
    view.setUint16(10, dosTime, true);
    view.setUint16(12, dosDate, true);
    view.setUint32(14, crc, true);
    view.setUint32(18, compressedSize, true);
    view.setUint32(22, size, true);
    view.setUint16(26, nameBytes.length, true);
    view.setUint16(28, 0, true);
    header.set(nameBytes, 30);
    this.entries.push({ name: nameBytes, method, crc, compressedSize, size, offset: this.offset, dosTime, dosDate });
    this.parts.push(header as BlobPart, data as BlobPart);
    this.offset += header.length + compressedSize;
  }

  /** Finishes the archive with its central directory. */
  toBlob(): Blob {
    const directory: BlobPart[] = [];
    let directorySize = 0;
    for (const entry of this.entries) {
      const record = new Uint8Array(46 + entry.name.length);
      const view = new DataView(record.buffer);
      view.setUint32(0, 0x02014b50, true);
      view.setUint16(4, 20, true);
      view.setUint16(6, 20, true);
      view.setUint16(8, UTF8_FLAG, true);
      view.setUint16(10, entry.method, true);
      view.setUint16(12, entry.dosTime, true);
      view.setUint16(14, entry.dosDate, true);
      view.setUint32(16, entry.crc, true);
      view.setUint32(20, entry.compressedSize, true);
      view.setUint32(24, entry.size, true);
      view.setUint16(28, entry.name.length, true);
      view.setUint32(42, entry.offset, true);
      record.set(entry.name, 46);
      directory.push(record as BlobPart);
      directorySize += record.length;
    }
    const end = new Uint8Array(22);
    const endView = new DataView(end.buffer);
    endView.setUint32(0, 0x06054b50, true);
    endView.setUint16(8, this.entries.length, true);
    endView.setUint16(10, this.entries.length, true);
    endView.setUint32(12, directorySize, true);
    endView.setUint32(16, this.offset, true);
    return new Blob([...this.parts, ...directory, end as BlobPart], { type: "application/zip" });
  }
}
