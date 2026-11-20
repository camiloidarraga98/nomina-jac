#if os(iOS)
import CryptoKit
import Foundation
import UIKit

@MainActor
final class TeamAttendanceDevice {
    static let shared = TeamAttendanceDevice()
    private let credentials = KeychainSessionStore(account: "team-attendance-kiosk-v1")
    private let protection = KeychainSessionStore(account: "team-attendance-file-v1")
    private let session: URLSession
    private var syncing = false
    private var nextAttempt = Date.distantPast
    private var retryDelay: TimeInterval = 2
    private var cameraInUse = false

    private struct Device: Codable { let id, secret: String; var name: String; var paired: Bool }
    private struct Person: Codable, Equatable { let id, name: String; let code: String?; let revision: Int; let enrollment: String? }
    private struct Roster: Decodable { let people: [Person] }
    private struct Reference: Codable {
        let id, employee, device: String
        let revision: Int
        let expires: Date
        let signingKey: Data
        let signature: AttendanceFaceSignature
    }
    private struct Punch: Codable {
        let id, employee, movement, occurredAt, enrollment, signature: String
        var photo: Data?
    }
    private struct LastPunch: Codable {
        let employee, movement, occurredAt: String
    }
    private struct Local: Codable {
        var roster: [Person] = []
        var refreshed: Date?
        var references: [String: Reference] = [:]
        var pending: [Punch] = []
        var blocked: [String] = []
        var lastPunch: LastPunch?
    }
    private struct RemoteError: LocalizedError {
        let status: Int, message: String
        var errorDescription: String? { message }
    }
    private var local: Local?
    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 10
        session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }
    private static func uuid() -> String { UUID().uuidString.lowercased() }
    private static func photoHash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private func device() throws -> Device? {
        guard let value = try credentials.load() else { return nil }
        return try JSONDecoder().decode(Device.self, from: Data(value.utf8))
    }
    private func saveDevice(_ value: Device) throws {
        try credentials.save(String(decoding: try JSONEncoder().encode(value), as: UTF8.self))
    }
    var isPaired: Bool { (try? device()?.paired) == true }
    private func paired() throws -> Device {
        guard let value = try device(), value.paired else { throw APIError.message("Este equipo requiere vinculación por un administrador.") }
        return value
    }
    private func key() throws -> SymmetricKey {
        if let saved = try protection.load() {
            guard let data = Data(base64Encoded:saved), data.count == 32 else { throw APIError.message("La protección local no está disponible.") }
            return SymmetricKey(data:data)
        }
        let fresh = SymmetricKey(size:.bits256)
        try protection.save(fresh.withUnsafeBytes { Data($0).base64EncodedString() })
        return fresh
    }
    private func file(_ d:Device) throws -> URL {
        try AttendanceStorage.directory().appendingPathComponent("equipo-"+d.id+".sealed")
    }
    private func ledger(_ d:Device) throws -> Local {
        if let local { return local }
        let path = try file(d)
        if !FileManager.default.fileExists(atPath:path.path) { return Local() }
        let box = try AES.GCM.SealedBox(combined:Data(contentsOf:path))
        let data = try AES.GCM.open(box,using:key(),authenticating:Data(d.id.utf8))
        let decoded = try JSONDecoder().decode(Local.self,from:data)
        local=decoded
        return decoded
    }
    private func save(_ state:Local,_ d:Device) throws {
        let box = try AES.GCM.seal(JSONEncoder().encode(state),using:key(),authenticating:Data(d.id.utf8))
        guard let bytes = box.combined else { throw APIError.message("No se pudo proteger la marcación pendiente.") }
        try bytes.write(to:file(d),options:JACFileSecurity.writeOptions)
        local=state
    }
    func pair(name:String, client:PayrollClient) async throws {
        guard client.baseURL == PayrollClient.productionURL, !client.isAttendancePilot else { throw APIError.message("Abre la cuenta administradora de JAC.") }
        var d: Device
        if let previous = try device() { d=previous }
        else {
            let secret=SymmetricKey(size:.bits256).withUnsafeBytes { Data($0).map { String(format:"%02x",$0) }.joined() }
            d=Device(id:Self.uuid(),secret:secret,name:name,paired:false)
            try saveDevice(d)
        }
        let hash=SHA256.hash(data:Data(d.secret.utf8)).map { String(format:"%02x",$0) }.joined()
        _ = try await client.sharedAttendanceAdmin(["action":"pair","id":d.id,"hash":hash,"name":name])
        d.paired=true; d.name=name
        try saveDevice(d)
    }
    private func request(_ d:Device, punch:Punch? = nil) async throws -> Data {
        var r=URLRequest(url: PayrollClient.productionURL.appendingPathComponent("api/team-attendance/kiosk"))
        r.httpShouldHandleCookies=false
        r.setValue("JAC-Kiosk "+d.secret,forHTTPHeaderField:"Authorization")
        r.setValue(d.id,forHTTPHeaderField:"X-JAC-Device")
        if let punch {
            r.httpMethod="POST";r.setValue("application/json",forHTTPHeaderField:"Content-Type")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.withoutEscapingSlashes]
            r.httpBody = try encoder.encode(punch)
        }
        let (data,response)=try await session.data(for:r)
        guard let http=response as? HTTPURLResponse else {throw URLError(.badServerResponse)}
        if !(200..<300).contains(http.statusCode) {
            let msg=(try? JSONSerialization.jsonObject(with:data) as? [String:String])?["error"]
            throw RemoteError(status:http.statusCode,message:msg ?? "El servidor no confirmó la operación.")
        }
        return data
    }
    private func refresh(_ d:Device, allowCached:Bool) async throws -> Bool {
        do {
            let data=try await request(d)
            let roster=try JSONDecoder().decode(Roster.self,from:data)
            var state=try ledger(d)
            let now=Date(), previous=state.roster, count=state.references.count
            state.roster=roster.people
            state.references=state.references.filter { employee, ref in
                ref.expires > Date() && ref.device == d.id && ref.employee == employee &&
                roster.people.contains { $0.id == employee && $0.revision == ref.revision && ($0.enrollment == nil || $0.enrollment == ref.id) }
            }
            if previous != state.roster || count != state.references.count || now.timeIntervalSince(state.refreshed ?? .distantPast)>60 {
                state.refreshed=now
                try save(state,d)
            }
            return true
        } catch {
            if let remote=error as? RemoteError, remote.status==403 {
                var state=try ledger(d);state.roster=[];state.references=[:];state.refreshed=nil;try save(state,d)
                throw remote
            }
            guard allowCached, error is URLError || (error as? RemoteError).map({ $0.status>=500 }) == true,
                  let saved=try ledger(d).refreshed, Date().timeIntervalSince(saved) < 12*3600 else {throw error}
            return false
        }
    }
    private func references(_ state:Local) -> [String:AttendanceFaceSignature] {
        var result=[String:AttendanceFaceSignature]()
        for person in state.roster {
            if let ref=state.references[person.id], ref.employee==person.id, ref.id==person.enrollment,
               ref.revision==person.revision, ref.expires>Date() { result[person.id]=ref.signature }
        }
        return result
    }
    private func sync(_ d:Device) async throws {
        guard !syncing, Date()>=nextAttempt else {return}
        syncing=true;defer {syncing=false}
        for punch in try ledger(d).pending {
            if try ledger(d).blocked.contains(punch.id) {continue}
            do {
                let data=try await request(d,punch:punch)
                let receipt=try JSONSerialization.jsonObject(with:data) as? [String:String]
                guard receipt?["id"]==punch.id, receipt?["receivedAt"] != nil else {throw URLError(.cannotParseResponse)}
                if let photo = punch.photo, receipt?["photoHash"] != Self.photoHash(photo) { throw URLError(.cannotParseResponse) }
                var state=try ledger(d);state.pending.removeAll{$0.id==punch.id};try save(state,d)
                nextAttempt = .distantPast;retryDelay=2
            } catch let e as RemoteError where [400,409].contains(e.status) {
                var state=try ledger(d)
                if !state.blocked.contains(punch.id) { state.blocked.append(punch.id) }
                if let i = state.pending.firstIndex(where: { $0.id == punch.id }) { state.pending[i].photo = nil }
                try save(state,d)
            } catch {
                nextAttempt=Date().addingTimeInterval(retryDelay);retryDelay=min(120,retryDelay*2)
                if let e=error as? RemoteError, e.status==403 {throw e};return
            }
        }
    }
    func info() async throws -> [String:Any] {
        guard isPaired else {return ["paired":false]}
        let d=try paired()
        do {_ = try await refresh(d,allowCached:true)}
        catch let e as RemoteError where e.status==403 {return ["paired":true,"revoked":true,"enrolled":[]]}
        catch {return ["paired":true,"unavailable":true,"enrolled":[]]}
        return ["paired":true,"enrolled":Array(references(try ledger(d)).keys)]
    }
    func status() async throws -> [String:Any] {
        guard let d = try device(), d.paired else { return ["paired":false] }
        let online = try await refresh(d,allowCached:true)
        if online {try await sync(d)}
        let state=try ledger(d)
        return ["paired":true,"name":d.name,"online":online,"pending":state.pending.count,"warning":state.blocked.isEmpty ? "" : "Hay marcaciones en conflicto en este kiosco. Pide supervisión antes de repetirlas."]
    }
    func capture(employee:String?, claimedCode:String?, movement:String?, enroll:Bool, client:PayrollClient, presenter:UIViewController,
                 allowed:() -> Bool) async throws -> [String:Any] {
        guard !cameraInUse else {throw APIError.message("Ya hay una lectura en curso.")}
        cameraInUse=true;defer {cameraInUse=false}
        let d=try paired()
        let online=try await refresh(d,allowCached:movement != nil)
        var state=try ledger(d)
        let claimed=claimedCode?.trimmingCharacters(in:.whitespacesAndNewlines) ?? ""
        let expected=state.roster.first { p in
            if !claimed.isEmpty {return p.code?.caseInsensitiveCompare(claimed) == .orderedSame}
            return p.id==employee
        }
        if !claimed.isEmpty && expected == nil {throw APIError.message("No se encontró una ficha activa con ese código. Revisa tu código.")}
        if employee != nil && expected == nil {throw APIError.message("El perfil ya no está activo.")}
        if enroll, expected?.enrollment != nil {throw APIError.message("Este perfil ya tiene una inscripción. Retírala explícitamente antes de reemplazarla.")}
        let candidates=references(state)
        if !enroll && candidates.isEmpty {throw APIError.message("Inscribe primero los rostros en este kiosco desde tu cuenta administradora.")}
        try Task.checkCancellation()
        guard allowed() else {throw APIError.unauthorized}
        let reading = try await AttendanceFaceCamera.collect(for: expected?.name ?? "Registro de asistencia", from: presenter,
                                                             includePhoto: movement != nil, stillAllowed: allowed)
        let sample = reading.signature
        guard allowed() else {throw APIError.unauthorized}
        _ = try await refresh(d,allowCached:movement != nil)
        guard allowed() else {throw APIError.unauthorized}
        state=try ledger(d)
        let known=references(state)
        if enroll, let person=expected {
            guard state.roster.contains(where:{$0.id==person.id && $0.revision==person.revision && $0.enrollment==nil}) else {throw APIError.message("La ficha cambió durante la inscripción.")}
            // Include staged registrations too, even if their server acknowledgement was lost.
            if state.references.contains(where:{$0.key != person.id && sample.resembles($0.value.signature)}) {
                throw APIError.message("Perfil incorrecto. Este rostro se parece a otro perfil inscrito. Solicita revisión presencial.")
            }
            let reference:Reference
            if let staged=state.references[person.id] {
                guard sample.resembles(staged.signature) else {throw APIError.message("Perfil incorrecto. Retira la inscripción anterior antes de registrar otro rostro.")}
                reference=staged
            } else {
                reference=Reference(id:Self.uuid(),employee:person.id,device:d.id,revision:person.revision,expires:Date().addingTimeInterval(30*86400),signingKey:P256.Signing.PrivateKey().rawRepresentation,signature:sample)
                state.references[person.id]=reference;try save(state,d)
            }
            let publicKey=try P256.Signing.PrivateKey(rawRepresentation:reference.signingKey).publicKey.x963Representation.base64EncodedString()
            _ = try await client.sharedAttendanceAdmin(["action":"enroll","id":reference.id,"employee":person.id,"device":d.id,"revision":person.revision,"publicKey":publicKey],enrollmentCredential:d.secret)
            _ = try await refresh(d,allowCached:false)
            return ["ok":true]
        }
        guard let who=sample.identified(in:known), let person=state.roster.first(where:{$0.id==who}), let enrollment=person.enrollment else {
            if expected != nil {throw APIError.message("No se pudo confirmar el rostro de este perfil. Reintenta o pide supervisión. No se registró una marcación.")}
            throw APIError.message("No se obtuvo una coincidencia única. Reintenta o pide supervisión. No se registró una marcación.")
        }
        if let expected, expected.id != who {throw APIError.message("Perfil incorrecto. El rostro no corresponde al empleado seleccionado. No se registró una marcación.")}
        guard let movement else {return ["message":"El rostro coincide con la ficha de "+person.name+"."]}
        guard ["entry","exit"].contains(movement), employee==nil else {throw APIError.message("Movimiento no válido.")}
        let now=Date(), format=ISO8601DateFormatter()
        if let last=state.lastPunch, last.employee==who, last.movement==movement, let time=format.date(from:last.occurredAt.replacingOccurrences(of:".000Z",with:"Z")),
           abs(now.timeIntervalSince(time))<60 {throw APIError.message("Ya se tomó esta marcación hace menos de un minuto. Consulta su estado antes de repetirla.")}
        guard let ref=state.references[who], ref.id==enrollment else {throw APIError.message("La inscripción cambió. Intenta de nuevo.")}
        let id=Self.uuid(), occurred=format.string(from:now).replacingOccurrences(of:"Z",with:".000Z")
        guard let photo = reading.photo else { throw APIError.message("Vuelve a escanear para guardar la foto de la marcación.") }
        let signed=["jac-attendance-v2",d.id,who,enrollment,id,movement,occurred,Self.photoHash(photo)].joined(separator:"\n")
        let privateKey=try P256.Signing.PrivateKey(rawRepresentation:ref.signingKey)
        let signature=try privateKey.signature(for:Data(signed.utf8)).rawRepresentation.base64EncodedString()
        let punch=Punch(id:id,employee:who,movement:movement,occurredAt:occurred,enrollment:enrollment,signature:signature,photo:photo)
        state.pending.append(punch)
        state.lastPunch=LastPunch(employee:who,movement:movement,occurredAt:occurred)
        try save(state,d)
        if online {try await sync(d)}
        let finished=try ledger(d)
        if finished.blocked.contains(punch.id) {throw APIError.message("El servidor bloqueó la marcación. Pide revisión al administrador.")}
        return ["received":!finished.pending.contains(where:{$0.id==punch.id}),"name":person.name,"occurredAt":punch.occurredAt]
    }
}
#endif
