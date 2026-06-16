import AppKit
import SwiftUI

@MainActor
protocol SSHWorkspaceContainerViewDelegate: AnyObject {
    func sshWorkspaceContainerViewDidRequestCloseSidebar(_ container: SSHWorkspaceContainerView)
    func sshWorkspaceContainerView(_ container: SSHWorkspaceContainerView, didRequestConnect connection: SSHConnection)
}

@MainActor
final class SSHWorkspaceContainerView: NSView {
    static let sidebarWidth = SSHSidebarLayout.totalWidth

    private let terminalView: TerminalViewContainer
    private let sidebarContainer = NSView()
    private let sidebarAppearance: SSHSidebarAppearance
    private let tabProvider = SSHWindowTabProvider()
    private var sidebarPanelCollapseState: SSHSidebarCollapseState = .expanded
    private var sidebarHostingView: NSHostingView<SSHConnectionsSidebarView>!
    private var sidebarWidthConstraint: NSLayoutConstraint?
    private var sidebarZeroWidthConstraint: NSLayoutConstraint?

    weak var delegate: SSHWorkspaceContainerViewDelegate?

    var isSidebarVisible: Bool = true {
        didSet {
            guard oldValue != isSidebarVisible else { return }
            updateSidebarVisibility()
        }
    }

    var terminalViewContainer: TerminalViewContainer {
        terminalView
    }

    var currentSidebarWidth: CGFloat {
        sidebarWidthConstraint?.constant ?? sidebarPanelCollapseState.width
    }

    override var intrinsicContentSize: NSSize {
        terminalView.intrinsicContentSize
    }

    init(
        terminalView: TerminalViewContainer,
        viewModel: SSHConnectionsViewModel,
        config: Ghostty.Config? = nil
    ) {
        self.terminalView = terminalView
        self.sidebarAppearance = SSHSidebarAppearance(config: config)

        super.init(frame: .zero)

        tabProvider.windowProvider = { [weak self] in
            self?.window
        }
        let sidebarView = SSHConnectionsSidebarView(
            viewModel: viewModel,
            appearance: sidebarAppearance,
            tabProvider: tabProvider,
            onConnect: { [weak self] connection in
                guard let self else { return }
                self.delegate?.sshWorkspaceContainerView(self, didRequestConnect: connection)
            },
            onCollapseStateChange: { [weak self] state in
                self?.setSidebarPanelCollapseState(state)
            },
            onClose: { [weak self] in
                guard let self else { return }
                self.delegate?.sshWorkspaceContainerViewDidRequestCloseSidebar(self)
            }
        )
        let createdHostingView = NSHostingView(rootView: sidebarView)
        self.sidebarHostingView = createdHostingView

        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func toggleSidebar() {
        isSidebarVisible.toggle()
    }

    func setSidebarPanelCollapseState(_ state: SSHSidebarCollapseState) {
        sidebarPanelCollapseState = state
        sidebarWidthConstraint?.constant = state.width
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    func updateSidebarConfig(_ config: Ghostty.Config) {
        sidebarAppearance.config = config
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        tabProvider.refresh()
    }

    private func setup() {
        addSubview(sidebarContainer)
        addSubview(terminalView)
        sidebarContainer.addSubview(sidebarHostingView)

        sidebarContainer.translatesAutoresizingMaskIntoConstraints = false
        sidebarHostingView.translatesAutoresizingMaskIntoConstraints = false
        terminalView.translatesAutoresizingMaskIntoConstraints = false

        let width = sidebarContainer.widthAnchor.constraint(equalToConstant: sidebarPanelCollapseState.width)
        let zeroWidth = sidebarContainer.widthAnchor.constraint(equalToConstant: 0)
        sidebarWidthConstraint = width
        sidebarZeroWidthConstraint = zeroWidth

        NSLayoutConstraint.activate([
            sidebarContainer.topAnchor.constraint(equalTo: topAnchor),
            sidebarContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            sidebarContainer.bottomAnchor.constraint(equalTo: bottomAnchor),

            sidebarHostingView.topAnchor.constraint(equalTo: sidebarContainer.topAnchor),
            sidebarHostingView.leadingAnchor.constraint(equalTo: sidebarContainer.leadingAnchor),
            sidebarHostingView.bottomAnchor.constraint(equalTo: sidebarContainer.bottomAnchor),
            sidebarHostingView.trailingAnchor.constraint(equalTo: sidebarContainer.trailingAnchor),

            terminalView.topAnchor.constraint(equalTo: topAnchor),
            terminalView.leadingAnchor.constraint(equalTo: sidebarContainer.trailingAnchor),
            terminalView.bottomAnchor.constraint(equalTo: bottomAnchor),
            terminalView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        updateSidebarVisibility()
    }

    private func updateSidebarVisibility() {
        sidebarWidthConstraint?.isActive = isSidebarVisible
        sidebarZeroWidthConstraint?.isActive = !isSidebarVisible
        sidebarContainer.isHidden = !isSidebarVisible
        invalidateIntrinsicContentSize()
    }
}
