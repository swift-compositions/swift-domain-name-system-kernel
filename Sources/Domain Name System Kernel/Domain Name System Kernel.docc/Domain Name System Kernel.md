# ``Domain_Name_System_Kernel``

@Metadata {
    @DisplayName("Domain Name System Kernel")
    @TitleHeading("Swift Foundations")
}

The system DNS provider: typed host resolution through the unified `Kernel`
surface, bound to the provider-neutral `DNS.Resolving` seam.

## Overview

`DNS.Resolver.System` answers a `DNS.Query` by running the typed
`Kernel.Socket.Address.Info` `getaddrinfo` surface on an externally owned,
bounded `Kernel.Thread.Pool`.
The platform's complete resolution policy applies — `/etc/hosts`, NSS, search
domains, split DNS, and enterprise configuration — and results keep the
system resolver's order with no invented time-to-live.

Cancellation, timeout, and shutdown abandon logical delivery promptly; the
admitted worker keeps ownership of the `addrinfo` chain and frees it when the
uninterruptible OS call finishes. A full admission queue fails with a typed
capacity error rather than creating another thread, and the resolver never
shuts down the pool it borrows.

## Topics

### System Provider

- ``DNS/Resolver/System``
