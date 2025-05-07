class Crc32 {
  static const int _poly = 0x04C11DB7;

  static int compute(List<int> data) {
    var crcValue = 0xFFFFFFFF;
    final len = data.length;

    for (var i = 0; i < (len + 3) ~/ 4; i++) {
      var xbit = 0x80000000;
      var word = 0;

      // 构建 32 位字
      for (var j = 0; j < 4; j++) {
        if (i * 4 + j < len) {
          word |= data[i * 4 + j] << (j * 8);
        } else {
          word |= 0x00 << (j * 8);
        }
      }

      // 处理 32 位
      for (var bits = 0; bits < 32; bits++) {
        if ((crcValue & 0x80000000) != 0) {
          crcValue = (crcValue << 1) & 0xFFFFFFFF;
          crcValue ^= _poly;
        } else {
          crcValue = (crcValue << 1) & 0xFFFFFFFF;
        }
        if ((word & xbit) != 0) {
          crcValue ^= _poly;
        }
        xbit >>>= 1;
      }
      crcValue >>>= 0;
    }
    return crcValue >>> 0;
  }
}
