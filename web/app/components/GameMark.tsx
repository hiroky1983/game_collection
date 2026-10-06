import Image from "next/image";
import type { Game } from "../lib/games";

/// ゲームの目印。絵（`icon`）があればドット絵として整数倍で出し、無ければ絵文字を出す。
/// `scale` は 1 ドット何 px か（絵文字の大きさに合わせて呼び出し側が決める）。
export default function GameMark({
  game,
  scale,
  className,
}: {
  game: Pick<Game, "emoji" | "icon">;
  scale: number;
  className?: string;
}) {
  if (!game.icon) return <span className={className}>{game.emoji}</span>;
  return (
    <Image
      src={game.icon.src}
      alt=""
      width={game.icon.width * scale}
      height={game.icon.height * scale}
      unoptimized
      className="inline-block shrink-0 align-middle"
      style={{ imageRendering: "pixelated" }}
    />
  );
}
