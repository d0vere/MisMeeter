import Foundation

/// Simple FIFO optimized enough for this low-bandwidth mono audio stream.
/// It avoids `removeFirst()` for every packet by keeping a read index and compacting occasionally.
final class SampleFIFO {
    private var storage: [Int16] = []
    private var readIndex = 0

    var count: Int {
        storage.count - readIndex
    }

    func append(_ values: [Int16]) {
        storage.append(contentsOf: values)
    }

    func pop(_ count: Int) -> [Int16]? {
        guard self.count >= count else { return nil }

        let start = readIndex
        let end = start + count
        let result = Array(storage[start..<end])
        readIndex = end

        if readIndex > 4096 && readIndex > storage.count / 2 {
            storage.removeFirst(readIndex)
            readIndex = 0
        }

        return result
    }

    func clear() {
        storage.removeAll(keepingCapacity: true)
        readIndex = 0
    }
}
