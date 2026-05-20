import Foundation
import Testing
@testable import KeenSwitch

// MARK: - HashPasswordTests
//
// Тесты Digest-аутентификации Keenetic RCI: SHA256(challenge + MD5_HEX(login:realm:password)).
// Известный вектор вычисляется детерминированно — расхождение означает регрессию в auth-flow.

struct HashPasswordTests {

    @Test("Известный вектор: admin / Keenetic / password + challenge=abc123")
    func knownVector() {
        let hash = KeeneticRCIClient.hashPassword(
            login: "admin",
            realm: "Keenetic",
            password: "password",
            challenge: "abc123"
        )
        // MD5("admin:Keenetic:password") = 296acddc9964b6354fe0636983f166db
        // SHA256("abc123" + md5_hex) = ...
        #expect(hash == "e6d36cc6cf4982b28d5dcfede0871146e1fcb5d9762d341e53a4999ccea2151d")
    }

    @Test("Длина хэша всегда 64 символа hex (SHA256)")
    func hashLength() {
        let hash = KeeneticRCIClient.hashPassword(
            login: "admin",
            realm: "Keenetic",
            password: "hunter2",
            challenge: "deadbeef"
        )
        #expect(hash.count == 64)
        #expect(hash.allSatisfy { $0.isHexDigit })
    }

    @Test("Хэш детерминирован — одинаковые входы дают одинаковый результат")
    func deterministic() {
        let a = KeeneticRCIClient.hashPassword(
            login: "user", realm: "Keenetic", password: "pw", challenge: "x"
        )
        let b = KeeneticRCIClient.hashPassword(
            login: "user", realm: "Keenetic", password: "pw", challenge: "x"
        )
        #expect(a == b)
    }

    @Test("Разный challenge → разный итоговый хэш (защита от replay)")
    func challengeChangesHash() {
        let h1 = KeeneticRCIClient.hashPassword(
            login: "admin", realm: "Keenetic", password: "secret", challenge: "challenge-1"
        )
        let h2 = KeeneticRCIClient.hashPassword(
            login: "admin", realm: "Keenetic", password: "secret", challenge: "challenge-2"
        )
        #expect(h1 != h2)
    }

    @Test("Разный пароль → разный хэш")
    func passwordChangesHash() {
        let h1 = KeeneticRCIClient.hashPassword(
            login: "admin", realm: "Keenetic", password: "secret", challenge: "c"
        )
        let h2 = KeeneticRCIClient.hashPassword(
            login: "admin", realm: "Keenetic", password: "SECRET", challenge: "c"
        )
        #expect(h1 != h2)
    }

    @Test("Разный realm → разный хэш (MD5 включает realm)")
    func realmChangesHash() {
        let h1 = KeeneticRCIClient.hashPassword(
            login: "admin", realm: "Keenetic", password: "pw", challenge: "c"
        )
        let h2 = KeeneticRCIClient.hashPassword(
            login: "admin", realm: "Other", password: "pw", challenge: "c"
        )
        #expect(h1 != h2)
    }

    @Test("UTF-8 в пароле обрабатывается корректно")
    func utf8Password() {
        let hash = KeeneticRCIClient.hashPassword(
            login: "admin",
            realm: "Keenetic",
            password: "пароль🔒",
            challenge: "c"
        )
        #expect(hash.count == 64)
    }
}
