//
//  Copyright (C) 2015 Deepin Technology Co., Ltd.
//  Copyright (C) 2014 Tom Beckmann
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

using Clutter;
using Meta;

namespace Gala
{
	class DeepinBorderEffect : Effect
	{
		public DeepinBorderEffect ()
		{
			Object ();
		}

		public override void paint (EffectPaintFlags flags)
		{
			actor.continue_paint ();

			// draw outer rectangle
			Cogl.set_source_color4ub (0, 0, 0, 100);
			Cogl.Path.rectangle (0, 0, actor.width, actor.height);
			Cogl.Path.stroke ();

			Cogl.set_source_color4ub (255, 255, 255, 25);
			Cogl.Path.rectangle (0.5f, 0.5f, actor.width - 1, actor.height - 1);
			Cogl.Path.stroke ();
		}
	}

/**
 * Utility class which adds a border and a shadow to a Background
 */
#if HAS_MUTTER314
	class DeepinFramedBackground : BackgroundManager
#else
	class DeepinFramedBackground : Background
#endif
	{
		public bool enable_shadow { get; construct; }
		public bool enable_border { get; construct; }

		ShadowEffect shadow_effect;

		public DeepinFramedBackground (
			Screen screen, bool enable_shadow = true, bool enable_border = false)
		{
#if HAS_MUTTER314
			Object (screen: screen, enable_shadow: enable_shadow, enable_border: enable_border,
					monitor_index: screen.get_primary_monitor (), control_position: false);
#else
			Object (screen: screen, enable_shadow: enable_shadow, enable_border: enable_border,
					monitor: screen.get_primary_monitor (),
					settings: BackgroundSettings.get_default ().schema);
#endif
		}

		construct
		{
			if (enable_shadow) {
				var monitor_geom = DeepinUtils.get_primary_monitor_geometry (screen);

				// shadow effect, angle:90°, size:15, distance:5, opacity:50%
				shadow_effect = new ShadowEffect (monitor_geom.width, monitor_geom.height, 30, 5, 128);
				add_effect (shadow_effect);
			}
			if (enable_border) {
				add_effect (new DeepinBorderEffect ());
			}

			screen.monitors_changed.connect (on_monitors_changed);
		}

		~DeepinFramedBackground ()
		{
			screen.monitors_changed.disconnect (on_monitors_changed);
		}

		void on_monitors_changed ()
		{
			if (shadow_effect != null) {
				var monitor_geom = DeepinUtils.get_primary_monitor_geometry (screen);
				shadow_effect.update_size (monitor_geom.width, monitor_geom.height);
			}
#if HAS_MUTTER314
			update_background_actor ();
#endif
		}
	}
}
