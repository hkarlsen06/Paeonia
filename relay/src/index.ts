import { DurableObject } from "cloudflare:workers";
import {
  deliveryFor,
  isExpired,
  isTooLarge,
  MAX_SOCKETS_PER_ROOM,
  nextExpiryAlarm,
  SESSION_MS,
  socketToReplace,
  type Attachment,
} from "./room.ts";
import { roomName, verifyTicket } from "./ticket.ts";

/**
 * Live drawing relay. Each couple gets one room per channel (a Durable Object): the
 * widget canvas room, and one room for each game channel in the ticket. The room
 * forwards every message from one socket to the other person's sockets as is,
 * and never stores or reads the drawing. The app owns the message format.
 * Sockets of the same user (the Home tab and the canvas on one phone) never
 * hear from each other. A socket past its 10-minute session hears nothing more: the room
 * closes it before forwarding to it, and an alarm closes it when the room is quiet.
 */
interface Env {
  ROOMS: DurableObjectNamespace<CanvasRoom>;
  RELAY_TICKET_SECRET: string;
}

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
    this.expireSockets(Date.now());
    const now = Date.now();
    let sockets = this.ctx.getWebSockets().filter((socket) => !attachmentOf(socket).hasLeft);
    if (sockets.length >= MAX_SOCKETS_PER_ROOM) {
      // A phone that dropped its connection may have left a half-open socket in the room.
      const replace = socketToReplace(sockets.map(attachmentOf), userId, now);
      const stale = sockets.find((socket) => attachmentOf(socket).socketId === replace);
      if (!stale) return new Response("Room is full", { status: 429 });
      this.close(stale, 4002, "replaced by a newer connection");
      sockets = sockets.filter((socket) => socket !== stale);
    }
    const peers = sockets.filter((socket) => attachmentOf(socket).userId !== userId);
    const [client, server] = Object.values(new WebSocketPair());
    this.ctx.acceptWebSocket(server);
    const socketId = crypto.randomUUID();
    server.serializeAttachment({ userId, socketId, openedAt: now, closesAt: now + SESSION_MS } satisfies Attachment);
    server.send(JSON.stringify({ type: "welcome", id: socketId, peers: peers.length }));
    this.broadcast(server, JSON.stringify({ type: "joined", id: socketId }));
    await this.scheduleExpiryAlarm();
    return new Response(null, { status: 101, webSocket: client });
  }

  /** Closes the sockets whose session ended while nobody sent anything. */
  async alarm(): Promise<void> {
    this.expireSockets(Date.now());
    await this.scheduleExpiryAlarm();
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    if (!isTooLarge(message)) this.broadcast(ws, message);
    // Forward first: the message may be an erase or a clear, and dropping it
    // would bring the strokes back when the app reconnects.
    if (isExpired(attachmentOf(ws), Date.now())) this.expire(ws);
  }

  async webSocketClose(ws: WebSocket): Promise<void> {
    this.leave(ws);
  }

  async webSocketError(ws: WebSocket): Promise<void> {
    this.leave(ws);
  }

  private expireSockets(now: number): void {
    for (const socket of this.ctx.getWebSockets()) {
      const attachment = attachmentOf(socket);
      if (!attachment.hasLeft && isExpired(attachment, now)) this.expire(socket);
    }
  }

  private expire(ws: WebSocket): void {
    this.close(ws, 4001, "session expired");
  }

  private close(ws: WebSocket, code: number, reason: string): void {
    this.leave(ws);
    try {
      ws.close(code, reason);
    } catch {
      // Already closing.
    }
  }

  private async scheduleExpiryAlarm(): Promise<void> {
    const next = nextExpiryAlarm(this.ctx.getWebSockets().map(attachmentOf));
    if (next === null) return;
    const current = await this.ctx.storage.getAlarm();
    if (current === null || current > next) await this.ctx.storage.setAlarm(next);
  }

  /** Tells the others once, even when both the error and the close handler run. */
  private leave(ws: WebSocket): void {
    const attachment = attachmentOf(ws);
    if (attachment.hasLeft) return;
    ws.serializeAttachment({ ...attachment, hasLeft: true } satisfies Attachment);
    this.broadcast(ws, JSON.stringify({ type: "left", id: attachment.socketId }));
  }

  private broadcast(sender: WebSocket, message: string | ArrayBuffer): void {
    const { userId } = attachmentOf(sender);
    const now = Date.now();
    for (const peer of this.ctx.getWebSockets()) {
      const delivery = deliveryFor(attachmentOf(peer), userId, now);
      if (delivery === "expire") {
        this.expire(peer);
      } else if (delivery === "send") {
        try {
          peer.send(message);
        } catch {
          // The peer is closing. Its close handler tells the others.
        }
      }
    }
  }
}

function attachmentOf(socket: WebSocket): Attachment {
  return socket.deserializeAttachment() as Attachment;
}
