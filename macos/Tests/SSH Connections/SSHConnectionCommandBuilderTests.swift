import Testing
@testable import Ghostty

struct SSHConnectionCommandBuilderTests {
    @Test func buildsDefaultPortDestinationWithUsername() throws {
        let connection = SSHConnection(
            name: "API",
            host: "example.com",
            port: 22,
            username: "deploy"
        )

        let command = try SSHConnectionCommandBuilder().buildCommand(for: connection)

        #expect(command == "ssh deploy@example.com")
    }

    @Test func buildsNonDefaultPortAndQuotedPrivateKeyPath() throws {
        let connection = SSHConnection(
            name: "API",
            host: "example.com",
            port: 2222,
            username: "deploy",
            privateKeyPath: "/Users/me/.ssh/prod key"
        )

        let command = try SSHConnectionCommandBuilder().buildCommand(for: connection)

        #expect(command == "ssh -p 2222 -i '/Users/me/.ssh/prod key' deploy@example.com")
    }

    @Test func emptyUsernameTargetsHostOnly() throws {
        let connection = SSHConnection(name: "API", host: "example.com")

        let command = try SSHConnectionCommandBuilder().buildCommand(for: connection)

        #expect(command == "ssh example.com")
    }

    @Test func rejectsEmptyHost() {
        let connection = SSHConnection(name: "API", host: "   ")

        do {
            try SSHConnectionCommandBuilder().buildCommand(for: connection)
            Issue.record("Expected empty host validation to fail")
        } catch let error as SSHConnectionCommandBuilder.ValidationError {
            #expect(error == .emptyHost)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func quotesShellMetacharacters() throws {
        let connection = SSHConnection(
            name: "Unsafe",
            host: "example.com; touch /tmp/nope",
            username: "deploy$(whoami)",
            privateKeyPath: "/Users/me/.ssh/key; rm -rf"
        )

        let command = try SSHConnectionCommandBuilder().buildCommand(for: connection)

        #expect(command == "ssh -i '/Users/me/.ssh/key; rm -rf' 'deploy$(whoami)@example.com; touch /tmp/nope'")
    }

    @Test func buildsSurfaceConfigurationWithCommandOnly() throws {
        let connection = SSHConnection(name: "API", host: "example.com")

        let configuration = try SSHConnectionCommandBuilder().buildConfiguration(for: connection)

        #expect(configuration.command == "ssh example.com")
        #expect(configuration.initialInput == nil)
    }
}
