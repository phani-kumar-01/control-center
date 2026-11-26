// SPDX-License-Identifier: GPL-2.0+
/*!
 * Copyright (c) 2020-2026 TUXEDO Computers GmbH <tux@tuxedocomputers.com>
 *
 * This file is part of tuxedo-drivers.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, see <https://www.gnu.org/licenses/>.
 */

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/acpi.h>
#include <linux/hwmon.h>
#include <linux/version.h>
#include "clevo_interfaces.h"

#define DRIVER_NAME			"clevo_acpi"

struct clevo_platform_driver_data_t {
	struct acpi_device *adev;
	struct clevo_interface_t *clevo_interface;
	struct device *hwmon_dev;
};

static struct clevo_platform_driver_data_t *active_driver_data = NULL;

static int clevo_acpi_evaluate(struct acpi_device *device, u8 cmd, u32 arg, union acpi_object **result)
{
	int status;
	acpi_handle handle;
	u64 dsm_rev_dummy = 0x00; // Dummy 0 value since not used
	u64 dsm_func = cmd;
	union acpi_object *out_obj;
	guid_t clevo_acpi_dsm_uuid;

	// Integer package data for argument
	union acpi_object dsm_argv4_package_data[] = {
		{
			.integer.type = ACPI_TYPE_INTEGER,
			.integer.value = arg
		}
	};

	// Package argument
	union acpi_object dsm_argv4 = {
		.package.type = ACPI_TYPE_PACKAGE,
		.package.count = 1,
		.package.elements = dsm_argv4_package_data
	};

	status = guid_parse(CLEVO_ACPI_DSM_UUID, &clevo_acpi_dsm_uuid);
	if (status < 0)
		return -ENOENT;

	handle = acpi_device_handle(device);
	if (handle == NULL)
		return -ENODEV;

	out_obj = acpi_evaluate_dsm(handle, &clevo_acpi_dsm_uuid, dsm_rev_dummy, dsm_func, &dsm_argv4);
	if (!out_obj) {
		pr_err("failed to evaluate _DSM\n");
		status = -1;
	} else {
		if (!IS_ERR_OR_NULL(result))
			*result = out_obj;
		else
			ACPI_FREE(out_obj);
	}

	return status;
}

static int clevo_acpi_evaluate_pkgbuf(struct acpi_device *device, u8 cmd, u8 *arg, u32 length, union acpi_object **result)
{
	int status;
	acpi_handle handle;
	u64 dsm_rev_dummy = 0x00; // Dummy 0 value since not used
	u64 dsm_func = cmd;

	// Use a buffer inside a package
	union acpi_object args = {
		.buffer.type = ACPI_TYPE_BUFFER,
		.buffer.length = length,
		.buffer.pointer = arg,
	};

	// Package argument
	union acpi_object dsm_argv4 = {
		.package.type = ACPI_TYPE_PACKAGE,
		.package.count = 1,
		.package.elements = &args,
	};

	union acpi_object *out_obj;

	guid_t clevo_acpi_dsm_uuid;

	status = guid_parse(CLEVO_ACPI_DSM_UUID, &clevo_acpi_dsm_uuid);
	if (status < 0)
		return -ENOENT;

	handle = acpi_device_handle(device);
	if (handle == NULL)
		return -ENODEV;

	out_obj = acpi_evaluate_dsm(handle, &clevo_acpi_dsm_uuid, dsm_rev_dummy, dsm_func, &dsm_argv4);
	if (!out_obj) {
		pr_err("failed to evaluate _DSM\n");
		status = -1;
	} else {
		if (!IS_ERR_OR_NULL(result))
			*result = out_obj;
		else
			ACPI_FREE(out_obj);
	}

	return status;
}

static int clevo_acpi_interface_method_call(u8 cmd, u32 arg, union acpi_object **result_value)
{
	int status = 0;

	if (!IS_ERR_OR_NULL(active_driver_data)) {
		status = clevo_acpi_evaluate(active_driver_data->adev, cmd, arg, result_value);
	} else {
		pr_err("acpi method call exec, no driver data found\n");
		pr_err("..for method_call: %0#4x arg: %0#10x\n", cmd, arg);
		status = -ENODATA;
	}
	// pr_debug("clevo_acpi method_call: %0#4x arg: %0#10x result: %0#10x\n", cmd, arg, !IS_ERR_OR_NULL(result_value) ? *result_value : 0);

	return status;
}

static int clevo_acpi_interface_method_call_pkgbuf(u8 cmd, u8 *arg, u32 length, union acpi_object **result_value)
{
	int status = 0;

	if (!IS_ERR_OR_NULL(active_driver_data)) {
		status = clevo_acpi_evaluate_pkgbuf(active_driver_data->adev, cmd, arg, length, result_value);
	} else {
		pr_err("acpi method call exec, no driver data found\n");
		pr_err("..for method_call: %0#2x\n", cmd);
		status = -ENODATA;
	}

	return status;
}

struct clevo_interface_t clevo_acpi_interface = {
	.string_id = CLEVO_INTERFACE_ACPI_STRID,
	.method_call = clevo_acpi_interface_method_call,
	.method_call_pkgbuf = clevo_acpi_interface_method_call_pkgbuf,
};

static void clevo_acpi_notify(acpi_handle handle, u32 event, void *data)
{
	struct acpi_device *adev = data;
	u32 event_value = 0;
	union acpi_object *out_obj;
	int status;

	// struct clevo_acpi_driver_data_t *clevo_acpi_driver_data;

	status = clevo_acpi_evaluate(adev, 0x01, 0, &out_obj);
	if (!status) {
			if (out_obj->type == ACPI_TYPE_INTEGER) {
				event_value = (u32)out_obj->integer.value;
			} else {
				pr_err("return type not integer, use clevo_evaluate_method2\n");
			}
			ACPI_FREE(out_obj);
	}
	pr_debug("clevo_acpi event: %0#6x, clevo event value: %0#6x\n", event, event_value);

	// clevo_acpi_driver_data = container_of(&device, struct clevo_acpi_driver_data_t, adev);
	if (!IS_ERR_OR_NULL(clevo_acpi_interface.event_callb)) {
		// Execute registered callback
		clevo_acpi_interface.event_callb(event);
	}
}


static umode_t clevo_hwmon_is_visible(const void *drvdata,
				      enum hwmon_sensor_types type,
				      u32 attr, int channel)
{
	switch (type) {
	case hwmon_fan:
		if (channel >= 0 && channel < 2 &&
		    (attr == hwmon_fan_input || attr == hwmon_fan_label))
			return 0444;
		break;
	case hwmon_temp:
		if (channel >= 0 && channel < 2 &&
		    (attr == hwmon_temp_input || attr == hwmon_temp_label))
			return 0444;
		break;
	case hwmon_pwm:
		if (channel >= 0 && channel < 2 && attr == hwmon_pwm_input)
			return 0444;
		break;
	default:
		break;
	}

	return 0;
}

static int clevo_hwmon_read_string(struct device *dev,
				   enum hwmon_sensor_types type,
				   u32 attr, int channel, const char **str)
{
	switch (type) {
	case hwmon_fan:
		if (attr == hwmon_fan_label) {
			*str = (channel == 0) ? "CPU Fan" : "GPU Fan";
			return 0;
		}
		break;
	case hwmon_temp:
		if (attr == hwmon_temp_label) {
			*str = (channel == 0) ? "CPU" : "GPU";
			return 0;
		}
		break;
	default:
		break;
	}

	return -EOPNOTSUPP;
}

static int clevo_hwmon_read(struct device *dev, enum hwmon_sensor_types type,
			  u32 attr, int channel, long *val)
{
	struct clevo_platform_driver_data_t *data = dev_get_drvdata(dev);
	union acpi_object *out_obj = NULL;
	int status;

	if (!data || !data->adev)
		return -ENODEV;

	switch (type) {
	case hwmon_fan:
		if (attr != hwmon_fan_input || channel < 0 || channel > 1)
			return -EOPNOTSUPP;
		status = clevo_acpi_evaluate(data->adev, 0x0C, 0, &out_obj);
		if (status)
			return status;
		if (!out_obj || out_obj->type != ACPI_TYPE_BUFFER ||
		    out_obj->buffer.length < 6) {
			if (out_obj)
				ACPI_FREE(out_obj);
			return -EIO;
		}
		{
			const u8 *buf = out_obj->buffer.pointer;
			u16 be16 = ((u16)buf[2 + 2 * channel] << 8) |
				   buf[3 + 2 * channel];
			ACPI_FREE(out_obj);
			*val = (be16 == 0 || be16 == 0xffff) ? 0 : (2156220L / be16);
		}
		return 0;

	case hwmon_temp:
		if (attr != hwmon_temp_input || channel < 0 || channel > 1)
			return -EOPNOTSUPP;
		status = clevo_acpi_evaluate(data->adev,
					     channel == 0 ? CLEVO_CMD_GET_FANINFO1 : CLEVO_CMD_GET_FANINFO2,
					     0, &out_obj);
		if (status)
			return status;
		if (!out_obj || out_obj->type != ACPI_TYPE_INTEGER) {
			if (out_obj)
				ACPI_FREE(out_obj);
			return -EIO;
		}
		{
			long temp = ((u32)out_obj->integer.value >> 16) & 0xFF;
			ACPI_FREE(out_obj);
			*val = temp * 1000L;
		}
		return 0;

	case hwmon_pwm:
		if (attr != hwmon_pwm_input || channel < 0 || channel > 1)
			return -EOPNOTSUPP;
		status = clevo_acpi_evaluate(data->adev,
					     channel == 0 ? CLEVO_CMD_GET_FANINFO1 : CLEVO_CMD_GET_FANINFO2,
					     0, &out_obj);
		if (status)
			return status;
		if (!out_obj || out_obj->type != ACPI_TYPE_INTEGER) {
			if (out_obj)
				ACPI_FREE(out_obj);
			return -EIO;
		}
		*val = (long)(out_obj->integer.value & 0xFF);
		ACPI_FREE(out_obj);
		return 0;

	default:
		return -EOPNOTSUPP;
	}
}

static const struct hwmon_channel_info * const clevo_hwmon_info[] = {
	HWMON_CHANNEL_INFO(fan,
			   HWMON_F_INPUT | HWMON_F_LABEL,
			   HWMON_F_INPUT | HWMON_F_LABEL),
	HWMON_CHANNEL_INFO(temp,
			   HWMON_T_INPUT | HWMON_T_LABEL,
			   HWMON_T_INPUT | HWMON_T_LABEL),
	HWMON_CHANNEL_INFO(pwm,
			   HWMON_PWM_INPUT,
			   HWMON_PWM_INPUT),
	NULL
};

static const struct hwmon_ops clevo_hwmon_ops = {
	.is_visible = clevo_hwmon_is_visible,
	.read = clevo_hwmon_read,
	.read_string = clevo_hwmon_read_string,
};

static const struct hwmon_chip_info clevo_hwmon_chip_info = {
	.ops = &clevo_hwmon_ops,
	.info = clevo_hwmon_info,
};

static int clevo_platform_probe(struct platform_device *pdev)
{
	struct clevo_platform_driver_data_t *driver_data;
	struct acpi_device *acpi;
	int error;

	acpi = ACPI_COMPANION(&pdev->dev);
	if (!acpi)
		return -ENODEV;

	error = acpi_dev_install_notify_handler(acpi, ACPI_ALL_NOTIFY, clevo_acpi_notify, acpi);
	if (error)
		return error;

	driver_data = devm_kzalloc(&pdev->dev, sizeof(*driver_data), GFP_KERNEL);
	if (!driver_data)
		return -ENOMEM;

	driver_data->adev = acpi;
	driver_data->clevo_interface = &clevo_acpi_interface;

	platform_set_drvdata(pdev, driver_data);
	active_driver_data = driver_data;

	driver_data->hwmon_dev = devm_hwmon_device_register_with_info(
		&pdev->dev, DRIVER_NAME, driver_data, &clevo_hwmon_chip_info, NULL);
	if (IS_ERR(driver_data->hwmon_dev)) {
		pr_warn("failed to register hwmon device (%ld)\n",
			PTR_ERR(driver_data->hwmon_dev));
		driver_data->hwmon_dev = NULL;
	}

	pr_debug("clevo_acpi driver add\n");

	// Add this interface
	clevo_keyboard_add_interface(&clevo_acpi_interface);

	pr_info("interface initialized\n");

	return 0;
}

#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 11, 0)
static int clevo_acpi_remove(struct platform_device *pdev)
#else
static void clevo_acpi_remove(struct platform_device *pdev)
#endif
{
	struct acpi_device *acpi;

	acpi = ACPI_COMPANION(&pdev->dev);
	acpi_dev_remove_notify_handler(acpi, ACPI_ALL_NOTIFY, clevo_acpi_notify);

	pr_debug("clevo_acpi driver remove\n");
	clevo_keyboard_remove_interface(&clevo_acpi_interface);
	active_driver_data = NULL;

#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 11, 0)
	return 0;
#endif
}

static int driver_suspend_callb(struct device *dev)
{
	pr_debug("driver suspend\n");
	return 0;
}

static int driver_resume_callb(struct device *dev)
{
	pr_debug("driver resume\n");
	return 0;
}

static DEFINE_SIMPLE_DEV_PM_OPS(clevo_driver_pm_ops, driver_suspend_callb, driver_resume_callb);

static const struct acpi_device_id clevo_acpi_device_ids[] = {
	{CLEVO_ACPI_RESOURCE_HID, 0},
	{"", 0}
};

static struct platform_driver clevo_platform_driver = {
	.driver = {
		.name = DRIVER_NAME,
		.acpi_match_table = clevo_acpi_device_ids,
		.pm = pm_ptr(&clevo_driver_pm_ops),
	},
	.probe = clevo_platform_probe,
	.remove = clevo_acpi_remove,
};

module_platform_driver(clevo_platform_driver);

MODULE_AUTHOR("TUXEDO Computers GmbH <tux@tuxedocomputers.com>");
MODULE_DESCRIPTION("Driver for Clevo ACPI interface");
MODULE_LICENSE("GPL");

MODULE_DEVICE_TABLE(acpi, clevo_acpi_device_ids);
