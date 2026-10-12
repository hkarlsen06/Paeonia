import { DurableObject } from "cloudflare:workers";
import { roomName, verifyTicket } from "./ticket.ts";

/**
 * Live drawing relay. Each couple gets one room per channel (a Durable Object): the
 * widget canvas room, and one room for each game channel in the ticket. The room
 * forwards every message from one socket to the other person's sockets as is,
 * and never stores or reads the drawing. The app owns the message format.
 * Sockets of the same user (the Home tab and the canvas on one phone) never
 * hear from each other.
 */
interface Env {
  ROOMS: DurableObjectNamespace<CanvasRoom>;
  RELAY_TICKET_SECRET: string;
}

type Attachment = { userId: string; socketId: string; closesAt: number; hasLeft?: boolean };

/** A socket must reconnect with a fresh ticket after this, so Convex checks access again. */
const SESSION_MS = 10 * 60_000;
const MAX_SOCKETS_PER_ROOM = 4;
const MAX_MESSAGE_BYTES = 4 * 1_048_576;

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname !== "/canvas") return new Response("Not found", { status: 404 });
    if (request.headers.get("Upgrade") !== "websocket") return new Response("Expected WebSocket", { status: 426 });
    const bearer = request.headers.get("Authorization")?.match(/^Bearer (.+)$/)?.[1] ?? "";
    const ticket = await verifyTicket(bearer, env.RELAY_TICKET_SECRET, Date.now());
    if (!ticket) return new Response("Unauthorized", { status: 401 });
    // The room trusts this header because only this Worker can reach the room.
    const headers = new Headers(request.headers);
    headers.set("X-Paeonia-User", ticket.userId);
    return env.ROOMS.getByName(roomName(ticket)).fetch(new Request(request, { headers }));
  },
};

export class CanvasRoom extends DurableObject<Env> {
  async fetch(request: Request): Promise<Response> {
    const userId = request.headers.get("X-Paeonia-User") ?? "";
    const sockets = this.ctx.getWebSockets();
    if (sockets.length >= MAX_SOCKETS_PER_ROOM) return new Response("Room is full", { status: 429 });
    const peers = sockets.filter((socket) => {
      const attachment = socket.deserializeAttachment() as Attachment;
      return attachment.userId !== userId && !attachment.hasLeft;
    });
    const [client, server] = Object.values(new WebSocketPair());
    this.ctx.acceptWebSocket(server);
    const socketId = crypto.randomUUID();
    server.serializeAttachment({ userId, socketId, closesAt: Date.now() + SESSION_MS } satisfies Attachment);
    server.send(JSON.stringify({ type: "welcome", id: socketId, peers: peers.length }));
    this.broadcast(server, JSON.stringify({ type: "joined", id: socketId }));
    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    const size = typeof message === "string" ? message.length : message.byteLength;
    if (size <= MAX_MESSAGE_BYTES) this.broadcast(ws, message);
    // Forward first: the message may be an erase or a clear, and dropping it
    // would bring the strokes back when the app reconnects.
    const { closesAt } = ws.deserializeAttachment() as Attachment;
    if (Date.now() > closesAt) {
      this.leave(ws);
      ws.close(4001, "session expired");
    }
  }

  async webSocketClose(ws: WebSocket): Promise<void> {
    this.leave(ws);
  }

  async webSocketError(ws: WebSocket): Promise<void> {
    this.leave(ws);
  }

  /** Tells the others once, even when both the error and the close handler run. */
  private leave(ws: WebSocket): void {
    const attachment = ws.deserializeAttachment() as Attachment;
    if (attachment.hasLeft) return;
    ws.serializeAttachment({ ...attachment, hasLeft: true } satisfies Attachment);
    this.broadcast(ws, JSON.stringify({ type: "left", id: attachment.socketId }));
  }

  private broadcast(sender: WebSocket, message: string | ArrayBuffer): void {
    const { userId } = sender.deserializeAttachment() as Attachment;
    for (const peer of this.ctx.getWebSockets()) {
      if ((peer.deserializeAttachment() as Attachment).userId === userId) continue;
      try {
        peer.send(message);
      } catch {
        // The peer is closing. Its close handler tells the others.
      }
    }
  }
}
