import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.RandomAccessFile;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.zip.Adler32;
import java.util.zip.CRC32;
import java.util.zip.Checksum;

/** Patches selected Miuix Editor onInvalidated() bodies inside a stored classes.dex. */
public final class MenuPatcher {
    private static final byte[] DEX_MAGIC = {'d', 'e', 'x', '\n'};
    private static final int EOCD_MIN = 22;
    private static final int EOCD_COMMENT = 65535;

    public static void main(String[] args) {
        try {
            if (args.length != 3) {
                System.err.println("Usage: MenuPatcher <apk> <menu.conf> <offsets.txt>");
                System.exit(2);
            }
            File apk = new File(args[0]);
            Map<String, Boolean> hide = readMenu(new File(args[1]));
            Map<String, Target> targets = readOffsets(new File(args[2]));
            patch(apk, hide, targets);
            System.out.println("PATCHED " + apk.getPath());
        } catch (Throwable error) {
            error.printStackTrace();
            System.exit(1);
        }
    }

    static void patch(File apk, Map<String, Boolean> hide, Map<String, Target> targets)
            throws Exception {
        try (RandomAccessFile file = new RandomAccessFile(apk, "rw")) {
            ZipEntry dex = findStoredEntry(file, "classes.dex");
            byte[] magic = new byte[4];
            file.seek(dex.dataOffset);
            file.readFully(magic);
            if (magic[0] != DEX_MAGIC[0] || magic[1] != DEX_MAGIC[1]
                    || magic[2] != DEX_MAGIC[2] || magic[3] != DEX_MAGIC[3]) {
                throw new IllegalStateException("classes.dex is not a DEX file");
            }
            int changed = 0;
            byte[] pad = new byte[Math.max(2, 64)];
            pad[0] = 0x0e;
            pad[1] = 0x00;
            for (Target target : targets.values()) {
                if (!Boolean.TRUE.equals(hide.get(target.id))) continue;
                int start = target.codeOffset + 16;
                int size = target.instructionBytes;
                if (start < 0 || size < 2 || start + size > dex.uncompressedSize) {
                    throw new IllegalStateException("Bad code range for " + target.id);
                }
                file.seek(dex.dataOffset + start);
                int remaining = size;
                boolean first = true;
                while (remaining > 0) {
                    int chunk = Math.min(remaining, pad.length);
                    if (!first) {
                        for (int i = 0; i < chunk; i++) pad[i] = 0x00;
                    } else if (chunk > 2) {
                        for (int i = 2; i < chunk; i++) pad[i] = 0x00;
                    }
                    file.write(pad, 0, chunk);
                    remaining -= chunk;
                    first = false;
                }
                pad[0] = 0x0e;
                pad[1] = 0x00;
                for (int i = 2; i < pad.length; i++) pad[i] = 0x00;
                changed++;
            }
            if (changed == 0) {
                System.out.println("No hidden actions; leaving stock DEX");
                return;
            }
            MessageDigest sha1 = MessageDigest.getInstance("SHA-1");
            hashRange(file, dex.dataOffset + 32, dex.uncompressedSize - 32, sha1);
            byte[] sha = sha1.digest();
            file.seek(dex.dataOffset + 12);
            file.write(sha);
            Adler32 adler = new Adler32();
            hashRange(file, dex.dataOffset + 12, dex.uncompressedSize - 12, adler);
            writeIntLe(file, dex.dataOffset + 8, (int) adler.getValue());
            CRC32 crc = new CRC32();
            hashRange(file, dex.dataOffset, dex.uncompressedSize, crc);
            int crcValue = (int) crc.getValue();
            writeIntLe(file, dex.localHeaderOffset + 14, crcValue);
            writeIntLe(file, dex.centralHeaderOffset + 16, crcValue);
        }
    }

    static Map<String, Boolean> readMenu(File path) throws IOException {
        Map<String, Boolean> hide = new HashMap<>();
        hide.put("search", true);
        hide.put("translate", true);
        hide.put("ask", true);
        hide.put("ai_rewrite", true);
        hide.put("phrases", true);
        if (!path.isFile()) return hide;
        for (String line : readLines(path)) {
            String trimmed = line.trim();
            if (trimmed.isEmpty() || trimmed.startsWith("#")) continue;
            int eq = trimmed.indexOf('=');
            if (eq <= 0) continue;
            String key = trimmed.substring(0, eq).trim();
            String value = trimmed.substring(eq + 1).trim();
            if (hide.containsKey(key)) hide.put(key, value.equals("1") || value.equalsIgnoreCase("true"));
        }
        return hide;
    }

    static Map<String, Target> readOffsets(File path) throws IOException {
        Map<String, Target> targets = new LinkedHashMap<>();
        for (String line : readLines(path)) {
            String trimmed = line.trim();
            if (trimmed.isEmpty() || trimmed.startsWith("#")) continue;
            String[] parts = trimmed.split("\\s+");
            if (parts.length != 4) throw new IllegalStateException("Bad offset line: " + trimmed);
            targets.put(parts[0], new Target(
                    parts[0],
                    parts[1],
                    Integer.parseInt(parts[2]),
                    Integer.parseInt(parts[3])
            ));
        }
        if (targets.isEmpty()) throw new IllegalStateException("No patch offsets");
        return targets;
    }

    private static List<String> readLines(File path) throws IOException {
        List<String> lines = new ArrayList<>();
        try (BufferedReader reader = new BufferedReader(
                new InputStreamReader(new FileInputStream(path), StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) lines.add(line);
        }
        return lines;
    }

    private static ZipEntry findStoredEntry(RandomAccessFile file, String name) throws IOException {
        long length = file.length();
        if (length < EOCD_MIN) throw new IOException("APK too small");
        int maxComment = (int) Math.min(EOCD_COMMENT, length - EOCD_MIN);
        byte[] tail = new byte[EOCD_MIN + maxComment];
        file.seek(length - tail.length);
        file.readFully(tail);
        int eocd = -1;
        for (int i = tail.length - EOCD_MIN; i >= 0; i--) {
            if (tail[i] != 'P' || tail[i + 1] != 'K' || tail[i + 2] != 5 || tail[i + 3] != 6) {
                continue;
            }
            int commentLen = (tail[i + 20] & 0xff) | ((tail[i + 21] & 0xff) << 8);
            if (i + EOCD_MIN + commentLen == tail.length) {
                eocd = i;
                break;
            }
        }
        if (eocd < 0) throw new IOException("ZIP end record missing");
        long cdSize = u32(tail, eocd + 12);
        long cdOffset = u32(tail, eocd + 16);
        if (cdSize > Integer.MAX_VALUE || cdOffset + cdSize > length) {
            throw new IOException("ZIP directory is too large");
        }
        byte[] central = new byte[(int) cdSize];
        file.seek(cdOffset);
        file.readFully(central);
        int pos = 0;
        while (pos + 46 <= central.length) {
            if (central[pos] != 'P' || central[pos + 1] != 'K'
                    || central[pos + 2] != 1 || central[pos + 3] != 2) {
                throw new IOException("Corrupt ZIP directory");
            }
            int method = u16(central, pos + 10);
            int crc = (int) u32(central, pos + 16);
            int compressed = (int) u32(central, pos + 20);
            int uncompressed = (int) u32(central, pos + 24);
            int nameLen = u16(central, pos + 28);
            int extraLen = u16(central, pos + 30);
            int commentLen = u16(central, pos + 32);
            int localOffset = (int) u32(central, pos + 42);
            String entryName = new String(central, pos + 46, nameLen, StandardCharsets.UTF_8);
            if (name.equals(entryName)) {
                if (method != 0) throw new IllegalStateException(name + " is compressed");
                file.seek(localOffset);
                byte[] local = new byte[30];
                file.readFully(local);
                int localName = u16(local, 26);
                int localExtra = u16(local, 28);
                ZipEntry entry = new ZipEntry();
                entry.centralHeaderOffset = cdOffset + pos;
                entry.localHeaderOffset = localOffset;
                entry.dataOffset = localOffset + 30L + localName + localExtra;
                entry.uncompressedSize = uncompressed;
                entry.crc = crc;
                if (compressed != uncompressed) throw new IllegalStateException(name + " size mismatch");
                return entry;
            }
            pos += 46 + nameLen + extraLen + commentLen;
        }
        throw new IOException(name + " missing from APK");
    }

    private static int u16(byte[] data, int offset) {
        return (data[offset] & 0xff) | ((data[offset + 1] & 0xff) << 8);
    }

    private static long u32(byte[] data, int offset) {
        return (data[offset] & 0xffL)
                | ((data[offset + 1] & 0xffL) << 8)
                | ((data[offset + 2] & 0xffL) << 16)
                | ((data[offset + 3] & 0xffL) << 24);
    }

    private static void writeIntLe(RandomAccessFile file, long offset, int value) throws IOException {
        file.seek(offset);
        file.write(value & 0xff);
        file.write((value >> 8) & 0xff);
        file.write((value >> 16) & 0xff);
        file.write((value >> 24) & 0xff);
    }

    private static void hashRange(
            RandomAccessFile file,
            long offset,
            int length,
            MessageDigest digest
    ) throws IOException {
        file.seek(offset);
        byte[] buffer = new byte[65536];
        int remaining = length;
        while (remaining > 0) {
            int read = file.read(buffer, 0, Math.min(remaining, buffer.length));
            if (read < 0) throw new IOException("Unexpected EOF while hashing DEX");
            digest.update(buffer, 0, read);
            remaining -= read;
        }
    }

    private static void hashRange(
            RandomAccessFile file,
            long offset,
            int length,
            Checksum checksum
    ) throws IOException {
        file.seek(offset);
        byte[] buffer = new byte[65536];
        int remaining = length;
        while (remaining > 0) {
            int read = file.read(buffer, 0, Math.min(remaining, buffer.length));
            if (read < 0) throw new IOException("Unexpected EOF while hashing DEX");
            checksum.update(buffer, 0, read);
            remaining -= read;
        }
    }

    static final class Target {
        final String id;
        final String descriptor;
        final int codeOffset;
        final int instructionBytes;

        Target(String id, String descriptor, int codeOffset, int instructionBytes) {
            this.id = id;
            this.descriptor = descriptor;
            this.codeOffset = codeOffset;
            this.instructionBytes = instructionBytes;
        }
    }

    private static final class ZipEntry {
        long centralHeaderOffset;
        long localHeaderOffset;
        long dataOffset;
        int uncompressedSize;
        int crc;
    }
}
