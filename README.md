# Formspec-based shop dialog

Inspired by Genshin Impact, this mod provides a graphical menu suitable for NPC or admin-configured shops. This mod uses the [`flow`](https://content.minetest.net/packages/luk3yx/flow/) Formspec library to handle visual layout, and the [`unified_money`](https://content.minetest.net/packages/Emojiminetest/unified_money/) library to handle currency transactions.

## API

### `shop_dialog.register_dialog(name,ShopDialog)`

Register a shop dialog.

* `name`: The identifier of the dialog.
* `ShopDialog`: A [`ShopDialog`](#shopdialog) object.

### `shop_dialog.show_to(name,dialog_id)`

Show a dialog to a player.

* `name`: The name of the player.
* `dialog_id`: The identifier of the dialog as registered in [`shop_dialog.register_dialog`](#shop_dialogregister_dialognameshopdialog).

## Objects

### `ShopDialogEntry`

A single entry in a `ShopDialog`.

```lua
{
    -- The item to be given
    item = ItemStack(),

    -- Description of the item
    -- Default to nothing.
    description = "",

    -- Money to buy the item.
    -- This uses the Unified Money system.
    cost = 10,

    -- Function returning the maximum allowed number of items to be brought.
    -- This cannot exceed 100, and if exceed, it will fallback to 100.
    -- If 0, the second returned value can be a string explaining the reason.
    -- Default to a dummy function that returns 100.
    max_amount = function(name) end,

    -- Callback after the item had been brought.
    -- Optional. If nil, nothing is called.
    after_buy = function(name,amount) end,
}
```

### `ShopDialog`

A shop dialog.

```lua
{
    -- The title to be shown on top of the shops
    -- Can be either string or function.
    title = "Dave Null's Shop",
    title = function(name) return "" end,

    -- The footnote to be shown under the shops
    -- Can be either string or function.
    footnote = "Hello World!",
    footnote = function(name) return "" end,

    -- Callback after one of the entries are brought
    -- Called after the entry's own callback
    -- Optional. If nil, nothing is called.
    after_buy = function(name,ShopDialogEntry,amount) end,

    entries = {
        -- List of ShopDialogEntry
    }
}
```
