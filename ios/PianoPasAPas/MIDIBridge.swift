import CoreMIDI
import Foundation

/// Écoute tous les claviers MIDI branchés à l'iPad (USB ou Bluetooth déjà appairé)
/// et transmet chaque message (note enfoncée, relâchée…) à la page web.
final class MIDIBridge {
    struct Device { let id: Int32; let name: String }

    /// Appelé (sur le fil principal) quand la liste des claviers change.
    var onDevicesChanged: (([Device]) -> Void)?
    /// Appelé (sur le fil principal) pour chaque message MIDI complet : identifiant du clavier + octets.
    var onMessage: ((Int32, [UInt8]) -> Void)?

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var connected = Set<Int32>()
    private(set) var devices: [Device] = []

    init() {
        MIDIClientCreateWithBlock("PianoPasAPas" as CFString, &client) { [weak self] notification in
            if notification.pointee.messageID == .msgSetupChanged {
                DispatchQueue.main.async { self?.refresh() }
            }
        }
        MIDIInputPortCreateWithBlock(client, "Entrée" as CFString, &inputPort) { [weak self] packetList, sourceRef in
            guard let self else { return }
            let id = Int32(truncatingIfNeeded: Int(bitPattern: sourceRef))
            var messages: [[UInt8]] = []
            for packet in packetList.unsafeSequence() {
                let length = Int(packet.pointee.length)
                let bytes = withUnsafeBytes(of: packet.pointee.data) { Array($0.prefix(length)) }
                messages.append(contentsOf: MIDIBridge.split(bytes))
            }
            guard !messages.isEmpty else { return }
            DispatchQueue.main.async { messages.forEach { self.onMessage?(id, $0) } }
        }
        refresh()
    }

    /// Relit la liste des claviers et se connecte aux nouveaux.
    func refresh() {
        var list: [Device] = []
        for i in 0..<MIDIGetNumberOfSources() {
            let source = MIDIGetSource(i)
            var uid: Int32 = 0
            MIDIObjectGetIntegerProperty(source, kMIDIPropertyUniqueID, &uid)
            var offline: Int32 = 0
            MIDIObjectGetIntegerProperty(source, kMIDIPropertyOffline, &offline)
            guard uid != 0, offline == 0 else { continue }
            var cfName: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(source, kMIDIPropertyDisplayName, &cfName)
            let name = (cfName?.takeRetainedValue() as String?) ?? "Clavier MIDI"
            if !connected.contains(uid) {
                // l'identifiant du clavier voyage avec chaque message (« refCon »)
                MIDIPortConnectSource(inputPort, source, UnsafeMutableRawPointer(bitPattern: Int(uid)))
                connected.insert(uid)
            }
            list.append(Device(id: uid, name: name))
        }
        connected = connected.intersection(list.map(\.id))
        devices = list
        onDevicesChanged?(list)
    }

    /// Un paquet peut contenir plusieurs messages (un accord, par exemple) : on les sépare.
    /// Gère le « running status » ; ignore les messages système (horloge, sysex…).
    static func split(_ bytes: [UInt8]) -> [[UInt8]] {
        var out: [[UInt8]] = []
        var status: UInt8 = 0
        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            if b >= 0xF8 { i += 1; continue }                      // temps réel : ignoré
            if b == 0xF0 {                                         // sysex : on saute jusqu'à F7
                while i < bytes.count && bytes[i] != 0xF7 { i += 1 }
                i += 1; status = 0; continue
            }
            if b >= 0xF0 { i += 1; status = 0; continue }          // autres messages système
            if b & 0x80 != 0 { status = b; i += 1 }
            guard status != 0 else { i += 1; continue }
            let kind = status & 0xF0
            let dataLength = (kind == 0xC0 || kind == 0xD0) ? 1 : 2
            guard i + dataLength <= bytes.count else { break }
            out.append([status] + bytes[i..<(i + dataLength)])
            i += dataLength
        }
        return out
    }
}
