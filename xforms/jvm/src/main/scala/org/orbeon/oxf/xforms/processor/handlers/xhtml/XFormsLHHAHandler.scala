/**
 * Copyright (C) 2010 Orbeon, Inc.
 *
 * This program is free software; you can redistribute it and/or modify it under the terms of the
 * GNU Lesser General Public License as published by the Free Software Foundation; either version
 * 2.1 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
 * without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU Lesser General Public License for more details.
 *
 * The full text of the license is available at http://www.gnu.org/copyleft/lesser.html
 */
package org.orbeon.oxf.xforms.processor.handlers.xhtml

import org.orbeon.oxf.xforms.XFormsUtils
import org.orbeon.oxf.xforms.analysis.ElementAnalysis
import org.orbeon.oxf.xforms.analysis.controls.{LHHA, LHHAAnalysis, StaticLHHASupport}
import org.orbeon.oxf.xforms.control.XFormsControl
import org.orbeon.oxf.xforms.control.controls.XFormsLHHAControl
import org.orbeon.oxf.xforms.processor.handlers.HandlerContext
import org.orbeon.oxf.xml.XMLConstants.XHTML_NAMESPACE_URI
import org.orbeon.oxf.xml.XMLReceiverSupport._
import org.orbeon.xforms.XFormsId
import org.xml.sax.Attributes
import org.orbeon.oxf.util.CoreUtils._

/**
 * Handler for label, help, hint and alert when those are placed outside controls.
 */
class XFormsLHHAHandler(
  uri            : String,
  localname      : String,
  qName          : String,
  attributes     : Attributes,
  matched        : AnyRef,
  handlerContext : AnyRef
) extends XFormsBaseHandlerXHTML(uri, localname, qName, attributes, matched, handlerContext, false, false) {

  import XFormsLHHAHandler._

  override def start(): Unit = {

    val lhhaEffectiveId = getEffectiveId

    implicit val xmlReceiver = xformsHandlerContext.getController.getOutput

    staticControlOpt match {
      case Some(staticLhha: LHHAAnalysis) if staticLhha.isForRepeat ⇒

        // Case where the LHHA has a dynamic representation and is in a lower nesting of repeats.
        // NOTE: In this case, we don't output a `for` attribute. Instead, the repeated control will use
        // `aria-*` attributes to point to this element.

        val containerAtts =
          getContainerAttributes(uri, localname, attributes, getPrefixedId, getEffectiveId, currentControlOrNull)

        withElement("span", prefix = xformsHandlerContext.findXHTMLPrefix, uri = XHTML_NAMESPACE_URI, atts = containerAtts) {
          for {
            currentLHHAControl ← currentControlOpt collect { case c: XFormsLHHAControl ⇒ c }
            externalValue      ← currentLHHAControl.externalValueOpt
            if externalValue.nonEmpty
          } locally {
            if (staticLhha.element.attributeValueOpt("mediatype") contains "text/html") {
              XFormsUtils.streamHTMLFragment(xmlReceiver, externalValue, currentLHHAControl.getLocationData, xformsHandlerContext.findXHTMLPrefix)
            } else {
              xmlReceiver.characters(externalValue.toCharArray, 0, externalValue.length)
            }
          }
        }

      case Some(staticLhha: LHHAAnalysis) if ! staticLhha.isForRepeat && ! staticLhha.isLocal ⇒

        // Non-repeated case of an external label.
        // Here we have a `for` attribute.

        def resolveControlOpt(staticControl: ElementAnalysis) =
          if (! isTemplate) {
            containingDocument.getControls.resolveObjectByIdOpt(lhhaEffectiveId, staticControl.staticId, null) collect {
              case control: XFormsControl ⇒ control
            }
          } else
            None

        val effectiveTargetControlOpt =
          staticLhha.effectiveTargetControlOrPrefixedIdOpt match {
            case Some(Left(effectiveTargetControl)) ⇒ resolveControlOpt(effectiveTargetControl)
            case Some(Right(_))                     ⇒ None
            case None                               ⇒ resolveControlOpt(staticLhha.directTargetControl)
          }

        val forEffectiveIdOpt =
          staticLhha.lhhaType == LHHA.Label option {
            staticLhha.effectiveTargetControlOrPrefixedIdOpt match {
              case Some(Left(effectiveTargetControl)) ⇒
                findTargetControlForEffectiveId(
                  xformsHandlerContext,
                  effectiveTargetControl,
                  XFormsId.getRelatedEffectiveId(lhhaEffectiveId, effectiveTargetControl.staticId)
                )
              case Some(Right(targetPrefixedId)) ⇒
                Some(XFormsId.getRelatedEffectiveId(lhhaEffectiveId, XFormsId.getStaticIdFromId(targetPrefixedId)))
              case None ⇒
                findTargetControlForEffectiveId(
                  xformsHandlerContext,
                  staticLhha.directTargetControl,
                  XFormsId.getRelatedEffectiveId(lhhaEffectiveId, staticLhha.directTargetControl.staticId)
                )
            }
          }

        handleLabelHintHelpAlert(
          lhhaAnalysis             = staticLhha,
          targetControlEffectiveId = XFormsId.getRelatedEffectiveId(lhhaEffectiveId, staticLhha.directTargetControl.staticId), // `id` placed on the label itself
          forEffectiveId           = forEffectiveIdOpt.flatten.orNull,
          lhha                     = staticLhha.lhhaType,
          requestedElementNameOpt  = None,
          controlOrNull            = effectiveTargetControlOpt.orNull, // to get the value
          isTemplate               = isTemplate,
          isExternal               = true
        )

      case _ ⇒ // `None if staticLhha.isLocal && ! staticLhha.isForRepeat`
        // Q: Can this happen? There should always be a static LHHA for the control, right?
    }
  }
}

object XFormsLHHAHandler {

  def findTargetControlForEffectiveId(
    handlerContext           : HandlerContext,
    targetControl            : ElementAnalysis,
    targetControlEffectiveId : String
  ): Option[String] = {

    // The purpose of this code is to identify the id of the target of the `for` attribute for the given target
    // control. In order to do that, we:
    //
    // - find which handler will process that control
    // - instantiate that handler
    // - so we can call `getForEffectiveId` on it
    //
    // NOTE: A possibly simpler better solution would be to always use the `foo$bar$$c.1-2-3` scheme for the `@for` id
    // of a control.
    handlerContext.getController.getHandler(targetControl.element, handlerContext) match {
      case handler: XFormsControlLifecyleHandler ⇒ Option(handler.getForEffectiveId(targetControlEffectiveId))
      case _                                     ⇒ None
    }
  }
}